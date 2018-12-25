require 'bundler/setup'
require 'slack_resources'
require 'slack_resources/generator/event_api/strong_hash'
require 'slack_resources/generator/event_api/examples_preparation'
require 'slack_resources/generator/event_api/to_schema'
require 'slack_resources/generator/event_api/write'
require 'slack_resources/generator/event_api/type_detection'

FileUtils.rm_r('./lib/slack_resources/resources/event_api')
SlackResources::Generator::Writer.new(
  output_dir: './lib/slack_resources/resources/event_api',
  data_dir: './lib/slack_resources/raw_data/event_api'
).execute!
