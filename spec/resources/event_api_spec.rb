require 'spec_helper'

RSpec.describe SlackResources::Resources::EventApi do
  let(:event_api) { SlackResources::Resources::EventApi }
  let(:event) { event_api.event_types.sample }

  10.times do
    it { expect(event_api.event_types).to be_present }
    it { expect(event_api.detail(event)).to be_a(Hash) }
    it { expect(event_api.example(event)).to be_a(Hash) }
    it { expect(event_api.schema(event)).to be_a(Hash) }
    it { expect(event_api.schemas).to be_a(Hash) }
  end
end
