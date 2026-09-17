# frozen_string_literal: true

require 'spec_helper'
require 'conductor/agents'
require 'json_schemer'
require_relative '../../../examples/agents/catalog'

RSpec.describe 'Runnable agent example contracts' do
  AgentExamples::EXAMPLES.each_key do |name|
    it "matches Python's #{name} configurations and validates against the agent schema" do
      example = AgentExamples.load(name)
      actual = Array(example.build(model: 'openai/gpt-4o-mini')).map do |agent|
        JSON.parse(JSON.generate(Conductor::Agents::ConfigSerializer.serialize(agent)))
      end
      fixtures = File.expand_path('../../fixtures/agents', __dir__)
      expected = JSON.parse(File.read(File.join(fixtures, 'examples', "#{name}.json")))
      expect(actual).to eq(expected)
      schema = JSONSchemer.schema(JSON.parse(File.read(File.join(fixtures, 'agent-schema.json'))))
      actual.each { |config| expect(schema.validate(config).to_a).to eq([]) }
    end
  end

  it 'loads all requested examples without starting workers or making HTTP calls' do
    expect(Conductor::Agents::AgentRuntime).not_to receive(:new)
    expect(AgentExamples::EXAMPLES.size).to eq(19)
    AgentExamples::EXAMPLES.each_key do |name|
      Array(AgentExamples.load(name).build).each do |agent|
        expect(Conductor::Agents::ConfigSerializer.serialize(agent)).to include('name', 'model')
      end
    end
  end

  it 'keeps external worker declarations out of the local worker pool' do
    agent = AgentExamples.load('33_external_workers').build
    registry = Conductor::Agents::ToolRegistry.new(Conductor::Agents::AgentConfig.new)
    expect(registry.tool_workers(agent).map(&:task_definition_name)).to eq(['format_response'])
    external = agent.tool('check_inventory')
    expect(external.func).to be_nil
    expect(external.input_schema['required']).to eq(['product_id'])
    expect(external.input_schema['properties']).to have_key('warehouse')
    expect(Conductor::Agents::ConfigSerializer.serialize(agent)['tools'].map { |t| t['toolType'] }).to eq(['worker'] * 4)
  end

  it 'preserves the three retry policies on registered task definitions' do
    agent = AgentExamples.load('02c_tool_retry_config').build
    registry = Conductor::Agents::ToolRegistry.new(Conductor::Agents::AgentConfig.new)
    definitions = registry.tool_workers(agent).map(&:task_def_template)
    expect(definitions.map(&:retry_count)).to eq([5, 3, 2])
    expect(definitions.map(&:retry_delay_seconds)).to eq([1, 5, 2])
    expect(definitions.map(&:retry_logic)).to eq(%w[EXPONENTIAL_BACKOFF FIXED LINEAR_BACKOFF])
  end
end
