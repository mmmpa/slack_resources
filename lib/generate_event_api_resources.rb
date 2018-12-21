require 'bundler/setup'
require 'slack_resources'

FileUtils.rm_r('./lib/slack_resources/resources/event_api')
SlackResources::Generator::Writer.new(
  output_dir: './lib/slack_resources/resources/event_api',
  data_dir: './lib/slack_resources/raw_data/event_api'
).execute!
