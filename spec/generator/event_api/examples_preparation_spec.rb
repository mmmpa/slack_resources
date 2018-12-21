require 'spec_helper'

RSpec.describe SlackResources::Generator::ExamplePreparation do
  subject(:result) do
    SlackResources::Generator::ExamplePreparation.new(
      examples_dir: Pathname('./spec/fixtures/examples'),
      added_examples_dir: Pathname('./spec/fixtures/_added_examples')
    ).execute!
  end

  let(:meta) { JSON.parse(File.read('./spec/fixtures/meta.json')) }

  it { expect(result.keys).to match_array(meta['types'] + ['event_callback']) }
  it do
    expect(result['message']['channel_type']).to eq(
      '_type' => 'enum',
      'target' => 'channel_type',
      'items' => ['app_home', 'channel', 'group', 'mpim', nil]
    )
  end
end
