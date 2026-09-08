# frozen_string_literal: true

require 'spec_helper'
require 'support/agent_tools'

RSpec.describe Conductor::Agents::ConfigSerializer do
  a = Conductor::Agents
  let(:model) { 'openai/gpt-4o' }

  def serialize(agent)
    described_class.serialize(agent)
  end

  it 'emits the always-present keys and drops nils and empties' do
    config = serialize(a::Agent.new(name: 'greeter', model: model))
    expect(config).to eq('name' => 'greeter', 'model' => model, 'maxTurns' => 25, 'timeoutSeconds' => 0,
                         'external' => false)
  end

  it 'emits strategy only for agents with sub-agents' do
    leaf = a::Agent.new(name: 'leaf', model: model, strategy: :parallel)
    expect(serialize(leaf)).not_to have_key('strategy')
    team = a::Agent.new(name: 'team', model: model, agents: [leaf], strategy: :parallel)
    expect(serialize(team)['strategy']).to eq('parallel')
    expect(serialize(team)['agents'].first['name']).to eq('leaf')
  end

  it 'inherits a missing team model from the first member and rejects model-less leaves' do
    team = a::Agent.new(name: 'bug_desk')
    team.add_agent a::Agent.new(name: 'triage', model: 'openai/gpt-4o-mini')
    team.add_agent a::Agent.new(name: 'filer', model: 'anthropic/claude-sonnet-4-5')
    expect(serialize(team)['model']).to eq('openai/gpt-4o-mini')

    expect { serialize(a::Agent.new(name: 'lonely')) }.to raise_error(a::ConfigurationError, /no model/)
    expect(serialize(a::Agent.new(name: 'ext', external: true))).not_to have_key('model')
  end

  it 'puts agent credentials at the top level and tool credentials under config' do
    agent = a::Agent.new(name: 'filer', model: model, credentials: ['GH_TOKEN'])
    agent.add_tool :create_issue, credentials: ['EXTRA']
    config = serialize(agent)
    expect(config['credentials']).to eq(['GH_TOKEN'])
    tool = config['tools'].first
    expect(tool['config']).to eq('credentials' => %w[GH_TOKEN EXTRA])
    expect(tool).not_to have_key('credentials')
    expect(tool['approvalRequired']).to be true
  end

  it 'serializes worker tools with schema, description and default output schema' do
    agent = a::Agent.new(name: 'w', model: model, tools: [:current])
    tool = serialize(agent)['tools'].first
    expect(tool).to eq(
      'name' => 'current', 'description' => 'Current', 'toolType' => 'worker',
      'inputSchema' => { 'type' => 'object',
                         'properties' => { 'city' => { 'type' => 'string' },
                                           'units' => { 'type' => 'string', 'default' => 'metric' } },
                         'required' => ['city'] },
      'outputSchema' => { 'type' => 'object', 'additionalProperties' => {} }
    )
  end

  it 'marks tools stateful when the agent is stateful' do
    agent = a::Agent.new(name: 'w', model: model, tools: [:current], stateful: true)
    expect(serialize(agent)['tools'].first['stateful']).to be true
  end

  it 'replaces the agent in an agent_tool config with agentConfig' do
    child = a::Agent.new(name: 'child', model: model)
    parent = a::Agent.new(name: 'parent', model: model, tools: [a::ToolDef.agent(child, optional: false)])
    tool = serialize(parent)['tools'].first
    expect(tool['toolType']).to eq('agent_tool')
    expect(tool['config']['agentConfig']['name']).to eq('child')
    expect(tool['config']['optional']).to be false
    expect(tool['config']).not_to have_key('agent')
  end

  it 'serializes instructions as string, prompt template or callable' do
    expect(serialize(a::Agent.new(name: 'x', model: model, instructions: ''))).not_to have_key('instructions')
    tpl = a::PromptTemplate.new(name: 'support_prompt', variables: { 'tone' => 'kind' }, version: 2)
    expect(serialize(a::Agent.new(name: 'x', model: model, instructions: tpl))['instructions']).to eq(
      'type' => 'prompt_template', 'name' => 'support_prompt', 'variables' => { 'tone' => 'kind' }, 'version' => 2
    )
    expect(serialize(a::Agent.new(name: 'x', model: model, instructions: -> { 'dynamic' }))['instructions']).to eq('dynamic')
  end

  it 'serializes guardrails of every kind' do
    agent = a::Agent.new(
      name: 'g', model: model,
      guardrails: [
        a::RegexGuardrail.new('x', name: 'rx', message: 'no x', on_fail: :retry),
        a::LlmGuardrail.new(model, 'policy', name: 'llm', max_tokens: 10),
        a::Guardrail.new(name: 'custom', on_fail: :fix) { |_| true },
        a::Guardrail.new(name: 'remote', position: :input)
      ]
    )
    expect(serialize(agent)['guardrails']).to eq([
                                                   { 'name' => 'rx', 'position' => 'output', 'onFail' => 'retry', 'maxRetries' => 3,
                                                     'guardrailType' => 'regex', 'patterns' => ['x'], 'mode' => 'block', 'message' => 'no x' },
                                                   { 'name' => 'llm', 'position' => 'output', 'onFail' => 'raise', 'maxRetries' => 3,
                                                     'guardrailType' => 'llm', 'model' => model, 'policy' => 'policy', 'maxTokens' => 10 },
                                                   { 'name' => 'custom', 'position' => 'output', 'onFail' => 'fix', 'maxRetries' => 3,
                                                     'guardrailType' => 'custom', 'taskName' => 'custom' },
                                                   { 'name' => 'remote', 'position' => 'input', 'onFail' => 'raise', 'maxRetries' => 3,
                                                     'guardrailType' => 'external', 'taskName' => 'remote' }
                                                 ])
  end

  it 'serializes handoffs including on_condition task names' do
    team = a::Agent.new(name: 'team', model: model, strategy: :swarm,
                        agents: [a::Agent.new(name: 'b', model: model)],
                        handoffs: [a::Handoff::OnToolResult.new(target: 'b', tool_name: 't', result_contains: 'x'),
                                   a::Handoff::OnCondition.new(target: 'b') { true }])
    expect(serialize(team)['handoffs']).to eq([
                                                { 'target' => 'b', 'type' => 'on_tool_result', 'toolName' => 't', 'resultContains' => 'x' },
                                                { 'target' => 'b', 'type' => 'on_condition', 'taskName' => 'team_handoff_b' }
                                              ])
  end

  it 'hoists member hands_off_to into a swarm team when no strategy was chosen' do
    triage = a::Agent.new(name: 'triage', model: model)
    filer = a::Agent.new(name: 'filer', model: model)
    triage.hands_off_to filer, on: 'ACTIONABLE'
    team = a::Agent.new(name: 'bug_desk')
    team.add_agents triage, filer
    config = serialize(team)
    expect(config['strategy']).to eq('swarm')
    expect(config['handoffs']).to eq([{ 'target' => 'filer', 'type' => 'on_text_mention', 'text' => 'ACTIONABLE' }])

    explicit = a::Agent.new(name: 'seq', strategy: :sequential)
    explicit.add_agents triage, filer
    expect(serialize(explicit)['strategy']).to eq('sequential')
    expect(serialize(explicit)).not_to have_key('handoffs')
  end

  it 'serializes memory, callbacks, prefill tools, metadata and numeric options' do
    memory = a::ConversationMemory.new(max_messages: 5)
    memory.add_user_message('hi')
    agent = a::Agent.new(name: 'm', model: model, memory: memory, max_tokens: 100, temperature: 0.2,
                         metadata: { 'team' => 'x' }, prefill_tools: [a::ToolDef.new(name: 't').call(a: 1)])
    agent.callback(:after_model) { |**_| nil }
    config = serialize(agent)
    expect(config['memory']).to eq('messages' => [{ 'role' => 'user', 'message' => 'hi' }], 'maxMessages' => 5)
    expect(config['callbacks']).to eq([{ 'position' => 'after_model', 'taskName' => 'm_after_model' }])
    expect(config['prefillTools']).to eq([{ 'toolName' => 't', 'arguments' => { 'a' => 1 } }])
    expect(config['metadata']).to eq('team' => 'x')
    expect(config['maxTokens']).to eq(100)
    expect(config['temperature']).to eq(0.2)
  end

  it 'serializes a router agent or router task reference' do
    child = a::Agent.new(name: 'c', model: model)
    by_agent = a::Agent.new(name: 'r', model: model, agents: [child], strategy: :router, router: child)
    expect(serialize(by_agent)['router']['name']).to eq('c')
    by_proc = a::Agent.new(name: 'r2', model: model, agents: [child], strategy: :router, router: ->(_ctx) { 'c' })
    expect(serialize(by_proc)['router']).to eq('taskName' => 'r2_router_fn')
  end

  it 'serializes output_type from a schema hash' do
    schema = { 'title' => 'Report', 'type' => 'object', 'properties' => {} }
    expect(serialize(a::Agent.new(name: 'o', model: model, output_type: schema))['outputType']).to eq(
      'schema' => schema, 'className' => 'Report'
    )
    expect(serialize(a::Agent.new(name: 'o', model: model, output_type: { class_name: 'X' }))['outputType']).to eq('className' => 'X')
  end
end
