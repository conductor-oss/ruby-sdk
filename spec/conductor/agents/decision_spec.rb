# frozen_string_literal: true

require 'spec_helper'
require 'conductor/agents'
require 'json_schemer'
require_relative '../../../examples/agentic_workflows/ai_decision_routing'
require_relative '../../../examples/agents/decision_router'
require_relative '../../../examples/agents/decision_tool'

RSpec.describe 'Decision routing' do
  let(:agents) { Conductor::Agents }
  let(:serializer) { agents::ConfigSerializer }

  it 'keeps a traditional decision as one SWITCH with branches and metadata outputs' do
    workflow = ExampleAiDecisionRouting.build(provider: 'openrouter').to_h
    decision = workflow['tasks'].first
    expect(workflow['tasks'].map { |task| task['type'] }).to eq(%w[SWITCH INLINE])
    expect(decision).to include('evaluatorType' => 'decision', 'expression' => 'route')
    expect(decision['inputParameters']).to include('model' => 'jev-1.13', 'provider' => 'openrouter',
                                                   'state' => '${workflow.input.request}')
    expect(decision['inputParameters']['questions']['route']['choices'].keys).to eq(%w[billing technical])
    expect(decision['decisionCases'].keys).to eq(%w[billing technical])
    expect(workflow['outputParameters'].keys).to eq(%w[selectedCase answers usage cost latencyMs result])
    expect(ExampleAiDecisionRouting.build(provider: nil).tasks.first.input_parameters).not_to have_key('provider')
  end

  it 'preserves the default value-param evaluator for existing switches' do
    task = Conductor::Workflow::Dsl::TaskRef.new(ref_name: 'route', task_name: 'route', task_type: 'SWITCH',
                                                 options: { expression: '${workflow.input.route}' }).to_workflow_task
    expect(task.evaluator_type).to eq('value-param')
    expect(task.expression).to eq('${workflow.input.route}')
  end

  it 'preserves JavaScript evaluators and expressions on existing switches' do
    task = Conductor::Workflow::Dsl::TaskRef.new(ref_name: 'route', task_name: 'route', task_type: 'SWITCH',
                                                 options: { expression: '$.route', evaluator_type: 'graaljs' }).to_workflow_task
    expect(task.evaluator_type).to eq('graaljs')
    expect(task.expression).to eq('$.route')
  end

  it 'serializes a decision selector without making the model-less parent external or starting a worker' do
    agent = ExampleDecisionRouter.build
    agent.router.config['provider'] = 'openrouter'
    config = serializer.serialize(agent)
    expect(config).to include('external' => false, 'synthesize' => false, 'strategy' => 'router')
    expect(config).not_to have_key('model')
    expect(config['router']).to eq('name' => 'support_selector_ruby', 'kind' => 'decision', 'model' => 'jev-1.13',
                                   'provider' => 'openrouter', 'questions' => agent.router.config['questions'])
    expect(config['agents'].map { |child| child['name'] }).to eq(%w[billing_ruby technical_ruby])
    registry = agents::ToolRegistry.new(agents::AgentConfig.new)
    expect(registry.workers_for(agent)).to be_empty
    schema = JSONSchemer.schema(JSON.parse(File.read(File.expand_path('../../fixtures/agents/agent-schema.json', __dir__))))
    expect(schema.validate(config).to_a).to be_empty
  end

  it 'omits an absent router provider and accepts symbol configuration keys' do
    agent = ExampleDecisionRouter.build
    agent.router.config = { model: 'jev-1.13', questions: { agent: { type: 'choice' } } }
    expect(serializer.serialize(agent)['router']).to eq('name' => 'support_selector_ruby', 'kind' => 'decision',
                                                        'model' => 'jev-1.13', 'questions' => { agent: { type: 'choice' } })
  end

  it 'rejects a non-decision tool as a router' do
    agent = ExampleDecisionRouter.build
    agent.router = agents::Tool.http('fetch', 'http://localhost')
    expect { serializer.serialize(agent) }.to raise_error(agents::ConfigurationError, /Only a decision Tool/)
  end

  it 'requires decision router model and questions' do
    agent = ExampleDecisionRouter.build
    [nil, ''].each do |model|
      agent.router.config['model'] = model
      expect { serializer.serialize(agent) }.to raise_error(agents::ConfigurationError, /requires 'model'/)
    end
    agent.router.config['model'] = 'jev-1.13'
    [nil, {}].each do |questions|
      agent.router.config['questions'] = questions
      expect { serializer.serialize(agent) }.to raise_error(agents::ConfigurationError, /requires 'questions'/)
    end
  end

  it 'uses the ordinary server-side tool serialization and worker path for a decision tool' do
    agent = ExampleDecisionTool.build
    tool = serializer.serialize(agent)['tools'].first
    expect(tool).to include('name' => 'classify_request_ruby', 'toolType' => 'decision', 'config' => agent.tools.first.config)
    expect(tool['inputSchema']['required']).to eq(['state'])
    expect(agent.tools.first).to be_server_side
    registry = agents::ToolRegistry.new(agents::AgentConfig.new)
    expect(registry.workers_for(agent)).to be_empty
  end
end
