class BloatJob < ActiveJob::Base
  queue_as :default

  def perform
    GC.disable if ENV["NO_GC"]

    num_rows = 5000
    num_cols = 10

    data = Array.new(num_rows) { Array.new(num_cols) { "x" * 1000 } }

    data.map { |row| row.join(",") }.join("\n")
  end
end
