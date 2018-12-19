module SlackResources
  require 'slack_resources/version' if File.exist?('./lib/slack_resources/version')

  require 'slack_resources/generator/event_api/strong_hash'
  require 'slack_resources/generator/event_api/examples_preparation'
end
