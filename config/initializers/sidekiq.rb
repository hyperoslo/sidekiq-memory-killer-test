# frozen_string_literal: true
Sidekiq.configure_server do |config|
  # Sidekiq can serve each job in a thread from an internal thread pool.
  # The `:concurrency` setting takes a number that means the number of
  # of workers to process jobs in the queue that will be spawn by Sidekiq.
  # Any libraries that use thread pools should be configured to match
  # the concurrency value specified for Sidekiq. Default is set to 5 threads
  # to match the default thread size of Active Record.
  #
  config.options[:concurrency] = ENV.fetch('SIDEKIQ_CONCURRENCY') { 5 }.to_i

  # Specifies the `environment` that Sidekiq will run in.
  #
  config.options[:environment] = ENV.fetch('RAILS_ENV') { 'development' }

  config.server_middleware do |chain|
    if ENV['SIDEKIQ_MEMORY_KILLER_MAX_RSS']
      chain.add SidekiqMiddleware::MemoryKiller
    end
  end

  config.on :startup do
    # Clear any connections that might have been obtained before starting
    # Sidekiq (e.g. in an initializer).
    #
    ActiveRecord::Base.clear_all_connections!
  end

  # Sets Active Record database maximum connection size to
  # the same number of workers spawn by Sidekiq.
  #
  Rails.application.config.after_initialize do
    db_config = ActiveRecord::Base.configurations[Rails.env]

    db_config['pool'] = ENV.fetch(
      'SIDEKIQ_DB_SIZE_POOL',
      Sidekiq.options[:concurrency]
    )

    ActiveRecord::Base.establish_connection(db_config)

    message = format(
      'Connection Pool size for Sidekiq Server is now: %s',
      ActiveRecord::Base.connection.pool.instance_variable_get(:@size)
    )

    Sidekiq.logger.debug(message)
  end
end
