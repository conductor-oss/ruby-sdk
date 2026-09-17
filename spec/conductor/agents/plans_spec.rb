# frozen_string_literal: true

require 'spec_helper'
require 'conductor/agents'

RSpec.describe Conductor::Agents::Plans do
  let(:tool) { Conductor::Agents::ToolDef.new(name: 'factorial', func: ->(n:) { (1..n).reduce(1, :*) }) }

  it 'serializes named slots and makes recovery tools discoverable to the worker runtime' do
    agent = Conductor::Agents.plan_execute(name: 'math', tools: [tool], model: 'mock/mockLLM',
                                           planner_instructions: 'Plan it', fallback_instructions: 'Recover', fallback_max_turns: 4,
                                           planner_context: [{ 'type' => 'text', 'text' => 'context' }])
    config = Conductor::Agents::ConfigSerializer.serialize(agent)
    expect(config).to include('strategy' => 'plan_execute', 'fallbackMaxTurns' => 4,
                              'plannerContext' => [{ 'type' => 'text', 'text' => 'context' }])
    expect(config['planner']).to include('name' => 'math_planner', 'instructions' => 'Plan it')
    expect(config['fallback']).to include('name' => 'math_fallback', 'instructions' => 'Recover')
    expect(config).not_to have_key('agents')
    expect(agent.all_agents.map(&:name)).to eq(%w[math math_planner math_fallback])
    registry = Conductor::Agents::ToolRegistry.new(Conductor::Agents::AgentConfig.new)
    expect(registry.tool_workers(agent).map(&:task_definition_name)).to eq(['factorial'])
  end

  it 'omits optional fields when there is no recovery agent' do
    agent = Conductor::Agents.plan_execute(name: 'math', tools: [tool], model: 'mock/mockLLM')
    expect(Conductor::Agents::ConfigSerializer.serialize(agent).keys).not_to include('fallback', 'fallbackMaxTurns', 'plannerContext')
  end

  it 'inherits a model from the planner and includes stateful named children' do
    planner = Conductor::Agents::Agent.new(name: 'planner', model: 'mock/mockLLM', stateful: true)
    agent = Conductor::Agents::Agent.new(name: 'math', strategy: :plan_execute, planner: planner, tools: [tool])
    expect(Conductor::Agents::ConfigSerializer.serialize(agent)['model']).to eq('mock/mockLLM')
    expect(agent.stateful_tree?).to be true
  end

  it 'rejects a missing planner and invalid named slots' do
    expect { Conductor::Agents::Agent.new(name: 'math', strategy: :plan_execute) }.to raise_error(Conductor::Agents::ConfigurationError, /requires planner/)
    expect { Conductor::Agents::Agent.new(name: 'math', planner: true) }.to raise_error(Conductor::Agents::ConfigurationError, /must be Agents/)
    expect { Conductor::Agents::Agent.new(name: 'math', fallback: 'fallback') }.to raise_error(Conductor::Agents::ConfigurationError, /must be Agents/)
  end
end
