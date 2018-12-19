require 'spec_helper'

RSpec.describe 'write' do
  it do
    require './lib/slack_resources/generator/event_api/write.rb'
    File.unlink('./tmp/schema.json') rescue nil
    Writer.new.execute!

    expect(File.read('./tmp/schema.json')).to eq(File.read('./lib/slack_resources/resources/event_api/schema.json'))
  end
end