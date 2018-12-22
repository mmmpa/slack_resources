module SlackResources
  require 'slack_resources/version' if File.exist?('./lib/slack_resources/version')

  require 'slack_resources/generator/event_api/strong_hash'
  require 'slack_resources/generator/event_api/examples_preparation'
  require 'slack_resources/generator/event_api/to_schema'
  require 'slack_resources/generator/event_api/type_detection'
  require 'slack_resources/generator/event_api/write'

  require 'slack_resources/resources/event_api'
end
