require 'spec_helper'

RSpec.describe SlackResources::Resources::EventApi do
  let(:event_api) { SlackResources::Resources::EventApi }
  let(:event) { event_api.event_types.sample }

  10.times do
    it { expect(event_api.event_types).to be_present }
    it { expect(event_api.details(event)).to be_present }
    it { expect(event_api.example(event)).to be_present }
    it { expect(event_api.schemas(event)).to be_present }
  end
end
