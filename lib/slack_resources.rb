module SlackResources
  require 'slack_resources/version' if File.exist?('./lib/slack_resources/version')

  require 'slack_resources/resources/event_api'
end
