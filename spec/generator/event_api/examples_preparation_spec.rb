require 'spec_helper'

RSpec.describe SlackResources::Generator::ExamplePreparation do
  subject(:result) do
    SlackResources::Generator::ExamplePreparation.new(
      examples_dir: Pathname('./spec/fixtures/examples_preparation/examples'),
      added_examples_dir: Pathname('./spec/fixtures/examples_preparation/_added_examples')
    ).execute!
  end

  describe 'includes added event type' do
    subject { result.keys }
    it { is_expected.to include('event_callback') }
  end

  describe 'includes all alternative event type' do
    subject { result.keys }
    it { is_expected.to match_array(%w[app_mention event_callback message message.im message.mpim]) }
  end

  describe 'squash types that have same event type to one event with enum' do
    subject { result['message']['channel_type'] }
    it {
      is_expected.to eq(
        '_type' => 'enum',
        'target' => 'channel_type',
        'items' => ['im', 'mpim', nil]
      )
    }
  end
end
