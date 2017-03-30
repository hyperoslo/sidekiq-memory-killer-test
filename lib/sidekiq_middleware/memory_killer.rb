# frozen_string_literal: true
# rubocop: disable AbcSize, MethodLength
#
# Adapted from Gitlab::SidekiqMiddleware::MemoryKiller
# https://github.com/gitlabhq/gitlabhq/blob/master/lib/gitlab/sidekiq_middleware/memory_killer.rb
#
# Copyright (c) 2011-2017 GitLab B.V.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require 'platform-api'

module SidekiqMiddleware
  class MemoryKiller
    # Default the RSS limit to 0, meaning the MemoryKiller is disabled
    #
    MAX_RSS = ENV.fetch('SIDEKIQ_MEMORY_KILLER_MAX_RSS') { 0 }.to_i

    # Give Sidekiq 15 minutes of grace time after exceeding the RSS limit
    #
    GRACE_TIME = ENV.fetch('SIDEKIQ_MEMORY_KILLER_GRACE_TIME') { 15 * 60 }.to_i

    # Create a mutex used to ensure there will be only one thread waiting to
    # shut Sidekiq down
    #
    MUTEX = Mutex.new

    def call(worker, job, _)
      yield

      current_rss = rss

      return unless MAX_RSS > 0 && current_rss > MAX_RSS

      Thread.new do
        # Return if another thread is already waiting to shut Sidekiq down
        return unless MUTEX.try_lock

        dyno = ENV['DYNO']

        Sidekiq.logger.warn "current RSS #{current_rss} exceeds " \
          "maximum RSS #{MAX_RSS}"

        Sidekiq.logger.warn "dyno '#{dyno}' will restart in #{GRACE_TIME}" \
          "seconds - [worker: #{worker.class}, jid: #{job['jid']}]"

        sleep(GRACE_TIME)

        Sidekiq.logger.warn "Restarting dyno (#{dyno}) - " \
          "[worker: #{worker.class}, jid: #{job['jid']}]"

        begin
          heroku = PlatformAPI.connect_oauth(ENV['HEROKU_API_KEY'])

          heroku.dyno.restart(ENV['HEROKU_APP_NAME'], dyno)
        rescue StandardError => ex
          $stdout.puts(ex.message)
          $stdout.puts(ex.backtrace)
        end
      end
    end

    private

    # Returns how much memory is allocated in RAM for the current process.
    #
    def rss
      Integer(`ps -o rss= -p #{::Process.pid}`)
    end
  end
end
