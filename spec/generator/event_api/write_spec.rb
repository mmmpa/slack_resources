require 'spec_helper'

RSpec.describe SlackResources::Generator::Writer do
  subject(:result) { SlackResources::Generator::Writer.new.execute! }
  subject(:alt_event_types) { result.map { |a| a[0] } }

  let(:meta) { JSON.parse(File.read('./spec/fixtures/meta.json')) }

  it { expect(alt_event_types).to match_array(meta['types'] + ['event_callback']) }
end
