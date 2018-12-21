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
    it { is_expected.to match_array(%w[app_mention event_callback message message.im message.mpim emoji_changed emoji_changed.add emoji_changed.remove]) }
  end

  describe 'squash types that have same event type to one event with enum' do
    let(:special_type_key) { SlackResources::Generator::TypeDetection::SPECIAL_TYPE }
    let(:multiple_type_value) { SlackResources::Generator::TypeDetection::MULTIPLE_EXAMPLES }

    context 'with single definition example' do
      subject { result['app_mention'].tap { |h| h.delete('_raw_example') } }
      it {
        is_expected.to eq(
          'type' => 'app_mention',
          'user' => 'U061F7AUR',
          'text' => '<@U0LAN0Z89> is it everything a river should be?',
          'ts' => '1515449522.000016',
          'channel' => 'C0LAN2Q65',
          'event_ts' => '1515449522000016'
        )
      }
    end

    context 'with message' do
      subject { result['message']['channel_type'] }
      it {
        is_expected.to eq(
          special_type_key => multiple_type_value,
          'target' => 'channel_type',
          'items' => ['im', 'mpim', nil]
        )
      }
    end

    context 'with emoji_changed' do
      subject { result['emoji_changed'].tap { |h| h.delete('_raw_example') } }
      it {
        is_expected.to eq(
          'type' => 'emoji_changed',
          'name' => {
            special_type_key => multiple_type_value,
            'target' => 'name',
            'items' => ['picard_facepalm', nil],
          },
          'value' => {
            special_type_key => multiple_type_value,
            'target' => 'value',
            'items' => ['https://my.slack.com/emoji/picard_facepalm/db8e287430eaa459.gif', nil],
          },
          'names' => {
            special_type_key => multiple_type_value,
            'target' => 'names',
            'items' => [nil, ['picard_facepalm']],
          },
          'subtype' => {
            special_type_key => multiple_type_value,
            'target' => 'subtype',
            'items' => %w[add remove],
          },
          'event_ts' => '1361482916.000004'
        )
      }
    end
  end
end
