require 'spec_helper'

RSpec.describe ::SlackResources::Generator::ToSchema do
  let(:params) { { example: example, url: 'https://example.com', preset: {} } }
  subject(:result) { SlackResources::Generator::ToSchema.new(params).execute! }
  subject(:properties) { result[0]['properties'] }
  subject(:new_definition) { result[1] }
  subject(:used_prop_names) { result[2] }

  describe 'makes object to object' do
    let(:example) { { 'obj' => { 'obj_prop' => 'value' } } }
    it { expect(properties).to eq({ 'obj' => { '$ref' => '#/definitions/obj' } }) }
    it {
      expect(new_definition).to eq(
        'obj' => {
          'type' => 'object',
          'description' => '(defined by script)',
          'properties' => { 'obj_prop' => { '$ref' => '#/definitions/obj_prop' } },
        },
        'obj_prop' => { 'type' => 'string' }
      )
    }
  end

  describe 'makes type const' do
    let(:example) { { 'type' => 'test' } }
    it { expect(properties).to eq({ 'type' => { 'const' => 'test' } }) }
  end

  describe 'makes unknown type specific type' do
    context 'with string' do
      let(:example) { { 'obj_prop' => 'obj_value' } }
      it { expect(properties).to eq({ 'obj_prop' => { '$ref' => '#/definitions/obj_prop' } }) }
      it { expect(new_definition).to eq('obj_prop' => { 'type' => 'string' }) }
    end

    context 'with integer', skip: 'picked up as time_integer' do
      let(:example) { { 'obj_prop' => 1 } }
      it { expect(properties).to eq({ 'obj_prop' => { '$ref' => '#/definitions/obj_prop' } }) }
      it { expect(new_definition).to eq('obj_prop' => { 'type' => 'number' }) }
    end

    context 'with array' do
      let(:example) { { 'obj_prop' => [] } }
      it { expect(properties).to eq({ 'obj_prop' => { '$ref' => '#/definitions/obj_prop' } }) }
      it { expect(new_definition).to eq('obj_prop' => { 'type' => 'array' }) }
    end

    context 'with hash' do
      let(:example) { { 'obj_prop' => { 'a' => 'b' } } }
      it { expect(properties).to eq({ 'obj_prop' => { '$ref' => '#/definitions/obj_prop' } }) }
      it {
        expect(new_definition).to eq(
          'a' => { 'type' => 'string' },
          'obj_prop' => {
            'description' => '(defined by script)',
            'properties' => {
              'a' => { '$ref' => '#/definitions/a' },
            },
            'type' => 'object',
          }
        )
      }
    end

    context 'with boolean' do
      let(:example) { { 'obj_prop' => true } }
      it { expect(properties).to eq({ 'obj_prop' => { 'type' => 'boolean' } }) }
      it('boolean properties not generate specific type') { expect(new_definition).to eq({}) }
    end
  end
end
