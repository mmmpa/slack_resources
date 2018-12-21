require 'spec_helper'

RSpec.describe SlackResources::Generator::Writer do
  before :all do
    FileUtils.rm_r('./tmp/spec') rescue nil

    @result = SlackResources::Generator::Writer.new(
      output_dir: './tmp/spec',
      data_dir: './spec/fixtures/write'
    ).execute!
  end

  subject(:alt_event_types) { @result.map { |a| a[0] } }
 
  let(:files) { Dir.glob('./spec/fixtures/write/examples/*.json') + Dir.glob('./spec/fixtures/write/_added_examples/*.json') }
  let(:expected_types) { files.map { |f| File.basename(f, '.json') }.uniq + ['emoji_changed'] }
  let(:all_event_files) { files.map { |f| File.basename(f) } + ['emoji_changed.json'] }
  let(:actual_example_files) { Dir.glob('./tmp/spec/examples/*.json').map { |f| File.basename(f) } }
  let(:actual_schemas_files) { Dir.glob('./tmp/spec/schemas/*.json').map { |f| File.basename(f) } }

  it { expect(alt_event_types).to match_array(expected_types) }
  it { expect(all_event_files).to match_array(actual_example_files) }
  it { expect(all_event_files).to match_array(actual_schemas_files) }
end
