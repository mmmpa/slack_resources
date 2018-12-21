require 'spec_helper'

RSpec.describe ::SlackResources::Generator::ToSchema do
  let(:params) { { example: example, url: 'https://example.com', preset: {} } }
  subject(:result) { SlackResources::Generator::ToSchema.new(params).execute! }
  subject(:properties) { result[0]['properties'] }
  subject(:new_definition) { result[1] }
  subject(:used_prop_names) { result[2] }

  describe 'makes object to object' do
    let(:example) { { obj: { obj_prop: :value } } }
    it { expect(properties).to eq({ 'obj' => { '$ref' => '#/definitions/obj' } }) }
    it {
      expect(new_definition).to eq({
                                     'obj' => { 'description' => '(defined by script)', 'properties' => { 'obj_prop' => { 'type' => 'string' } }, 'type' => 'object' },
                                     'obj_prop' => { 'type' => 'string' },
                                   })
    }
  end

  describe 'makes type const' do
    let(:example) { { type: :test } }
    it { expect(properties).to eq({ 'type' => { 'const' => 'test' } }) }
  end
end
