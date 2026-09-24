# frozen_string_literal: true

require 'spec_helper'
require 'support/agent_tools'

RSpec.describe Conductor::Agents::Tools do
  let(:weather) { SpecTools::Weather }

  describe 'tool def' do
    it 'names the tool after the method and humanizes the description' do
      td = weather[:current]
      expect(td).to be_a(Conductor::Agents::ToolDef)
      expect(td.name).to eq('current')
      expect(td.description).to eq('Current')
      expect(td.local?).to be true
    end

    it 'registers the tool globally so Agent#add_tool(:name) finds it' do
      expect(described_class.lookup(:current)).to equal(weather[:current])
    end

    it 'types required parameters from class defaults and optional ones from literals' do
      expect(weather[:current].input_schema).to eq(
        'type' => 'object',
        'properties' => {
          'city' => { 'type' => 'string' },
          'units' => { 'type' => 'string', 'default' => 'metric' }
        },
        'required' => ['city']
      )
    end

    it 'handles integers, booleans, floats, typed arrays, enums, nil and hash defaults' do
      schema = weather[:forecast].input_schema
      expect(schema['required']).to eq(%w[city tags])
      expect(schema['properties']).to eq(
        'city' => { 'type' => 'string' },
        'days' => { 'type' => 'integer', 'default' => 3 },
        'detailed' => { 'type' => 'boolean', 'default' => false },
        'tags' => { 'type' => 'array', 'items' => { 'type' => 'string' } },
        'mode' => { 'type' => 'string', 'enum' => %w[brief full], 'default' => 'brief' },
        'ratio' => { 'type' => 'number', 'default' => 0.5 },
        'extra' => {},
        'opts' => { 'type' => 'object', 'default' => {} }
      )
    end

    it 'defaults the output schema to an object' do
      expect(weather[:current].output_schema).to eq('type' => 'object', 'additionalProperties' => {})
    end

    it 'keeps the method callable as a normal method' do
      expect(weather.current(city: 'Lisbon')).to include(temp_c: 21.0)
      expect(weather[:current].func.call(city: 'Porto', units: 'imperial')[:summary]).to eq('Sunny in Porto (imperial)')
    end

    it 'rejects positional parameters' do
      expect { SpecTools::Refunds.tool(:positional) }.to raise_error(Conductor::Agents::ConfigurationError, /keyword/)
    end

    it 'raises for unknown methods and unknown options' do
      expect { weather.tool(:nope) }.to raise_error(Conductor::Agents::ConfigurationError, /no such method/)
      expect { weather.tool(:current, colour: 'red') }.to raise_error(Conductor::Agents::ConfigurationError, /unknown tool option/)
    end

    it 'treats keywords without defaults as required untyped properties' do
      expect(SpecTools::Plain[:lookup].input_schema).to eq(
        'type' => 'object',
        'properties' => { 'city' => {}, 'units' => { 'type' => 'string', 'default' => 'metric' } },
        'required' => ['city']
      )
    end

    it 'falls back to untyped properties when the AST is unavailable' do
      allow(Conductor::Agents::Tools::SchemaBuilder).to receive(:ast_of).and_return(nil)
      schema = Conductor::Agents::Tools::SchemaBuilder.input_schema(SpecTools::Plain.method(:lookup))
      expect(schema).to eq('type' => 'object', 'properties' => { 'city' => {}, 'units' => {} }, 'required' => ['city'])
    end
  end

  describe 'describe / requires_approval / tool_credentials' do
    it 'overrides the description' do
      expect(weather[:forecast].description).to eq('Multi-day forecast.')
    end

    it 'marks approval' do
      expect(SpecTools::Refunds[:issue_refund].approval_required).to be true
      expect(weather[:current].approval_required).to be false
    end

    it 'adds explicit credentials' do
      SpecTools::Github.tool_credentials(:dynamic_secret, 'DYN_KEY')
      expect(SpecTools::Github[:dynamic_secret].credentials).to eq(['DYN_KEY'])
    end
  end

  describe 'secret scanning' do
    it 'declares literal secret() names' do
      expect(SpecTools::Github[:create_issue].credentials).to eq(['GH_TOKEN'])
    end

    it 'declares every literal in secrets_env()' do
      expect(SpecTools::Github[:gh_cli].credentials).to eq(%w[GH_TOKEN GH_HOST])
    end

    it 'ignores dynamic names' do
      expect(SpecTools::Github[:dynamic_secret].credentials).not_to include('name')
    end
  end

  describe '#tool_defs' do
    it 'lists the tools of a module in definition order' do
      expect(weather.tool_defs.map(&:name)).to eq(%w[current forecast])
    end
  end
end
