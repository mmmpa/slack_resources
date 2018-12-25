require 'bundler/setup'
require 'slack_resources'
require 'slack_resources/generator/event_api/strong_hash'
require 'slack_resources/generator/event_api/examples_preparation'
require 'slack_resources/generator/event_api/to_schema'
require 'slack_resources/generator/event_api/write'
require 'slack_resources/generator/event_api/type_detection'

ENV['RUN_ENV'] = 'test'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
