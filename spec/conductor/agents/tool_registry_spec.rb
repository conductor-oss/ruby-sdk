# frozen_string_literal: true

require 'spec_helper'
require 'support/agent_tools'

RSpec.describe Conductor::Agents::ToolRegistry do
  a = Conductor::Agents
  let(:config) { a::AgentConfig.new(worker_poll_interval_ms: 50, worker_thread_count: 2) }
  let(:logger) { instance_double(Logger, warn: nil, info: nil, error: nil, debug: nil) }
  let(:registry) { described_class.new(config, logger: logger) }
  let(:weather) do
    agent = a::Agent.new(name: 'weather', model: 'openai/gpt-4o-mini', instructions: 'Answer weather questions.')
    agent.add_tool :current
    agent.add_tool a::ToolDef.http('fetch', 'http://x')
    agent
  end

  it 'builds one worker per local tool with the Python task definition defaults' do
    workers = registry.workers_for(weather, required_workers: ['current'])
    expect(workers.map(&:task_definition_name)).to eq(['current'])
    w = workers.first
    expect(w.register_task_def).to be true
    expect(w.overwrite_task_def).to be true
    expect(w.lease_extend_enabled).to be true
    expect(w.poll_interval).to eq(50)
    expect(w.thread_count).to eq(2)
    expect(w.domain).to be_nil
    td = w.task_def_template.to_h
    expect(td).to include('name' => 'current', 'retryCount' => 2, 'timeoutSeconds' => 0, 'timeoutPolicy' => 'RETRY',
                          'retryLogic' => 'LINEAR_BACKOFF', 'retryDelaySeconds' => 2, 'responseTimeoutSeconds' => 10,
                          'enforceSchema' => false, 'runtimeMetadata' => [])
  end

  it 'puts tool and agent credentials on runtimeMetadata' do
    filer = a::Agent.new(name: 'filer', model: 'm/x', credentials: ['ORG_KEY'])
    filer.add_tool :create_issue
    td = registry.workers_for(filer).first.task_def_template
    expect(td.runtime_metadata).to eq(%w[GH_TOKEN ORG_KEY])
  end

  it 'runs the tool through Dispatch' do
    worker = registry.workers_for(weather).first
    task = Conductor::Http::Models::Task.from_hash('taskId' => 't', 'inputData' => { 'city' => 'Lisbon', 'method' => 'current' })
    result = worker.execute(task)
    expect(result.status).to eq('COMPLETED')
    expect(result.output_data['temp_c']).to eq(21.0)
  end

  it 'inherits credentials through teams and combines them for shared tools' do
    first = a::Agent.new(name: 'first', model: 'm/x', tools: [SpecTools::Weather[:current]], credentials: ['FIRST'])
    second = a::Agent.new(name: 'second', model: 'm/x', tools: [SpecTools::Weather[:current]], credentials: ['SECOND'])
    team = a::Agent.new(name: 'team', agents: [first, second], credentials: ['TEAM'])
    workers = registry.tool_workers(team)
    expect(workers.size).to eq(1)
    expect(workers.first.task_def_template.runtime_metadata).to match_array(%w[TEAM FIRST SECOND])
  end

  it 'serves custom tool guardrails and function routers required by the server' do
    guard = a::Guardrail.new(name: 'tool_policy') { |content| content == 'safe' }
    tool = a::ToolDef.new(name: 'action', func: -> { {} }, guardrails: [guard])
    child = a::Agent.new(name: 'child', model: 'm/x', tools: [tool])
    team = a::Agent.new(name: 'team', agents: [child], strategy: :router, router: ->(prompt) { "#{prompt}_route" })
    workers = registry.workers_for(team, required_workers: %w[tool_policy team_router_fn])
    router = workers.find { |worker| worker.task_definition_name == 'team_router_fn' }
    task = Conductor::Http::Models::Task.new(input_data: { 'prompt' => 'child' })
    expect(router.execute(task).output_data).to eq('selected_agent' => 'child_route')
    policy = workers.find { |worker| worker.task_definition_name == 'tool_policy' }
    expect(policy.execute(Conductor::Http::Models::Task.new(input_data: { 'content' => 'safe' })).output_data['passed']).to be true
  end

  it 'registers hoisted condition handoffs using the parent name' do
    first = a::Agent.new(name: 'first', model: 'm/x')
    second = a::Agent.new(name: 'second', model: 'm/x')
    first.hands_off_to(second, on: ->(_context) { true })
    team = a::Agent.new(name: 'team', agents: [first, second])
    worker = registry.workers_for(team, required_workers: ['team_handoff_second']).first
    expect(worker.task_definition_name).to eq('team_handoff_second')
    expect(worker.execute(Conductor::Http::Models::Task.new(input_data: {})).output_data).to include('handoff' => true, 'target' => 'second')
  end

  it 'uses the first team member if a router raises, and an empty name without members' do
    router = ->(_prompt) { raise 'unavailable' }
    task = Conductor::Http::Models::Task.new(input_data: {})
    expect(a::SystemWorkers.router(router, ['first'], logger: logger).call(task)).to eq('selected_agent' => 'first')
    expect(a::SystemWorkers.router(router, [], logger: logger).call(task)).to eq('selected_agent' => '')
  end

  it 'registers system workers only when the server requires them and warns about unknown names' do
    agent = a::Agent.new(name: 'bug_desk', model: 'm/x')
    agent.stop_when 'ISSUE_FILED'
    agent.add_guardrail a::Guardrail.new(name: 'no_pii') { true }
    agent.callback(:before_model) { |**| nil }
    agent.add_handoff a::Handoff::OnCondition.new(target: 'filer') { true }

    names = registry.workers_for(agent, required_workers: %w[bug_desk_termination no_pii bug_desk_before_model
                                                             bug_desk_handoff_filer mystery_task]).map(&:task_definition_name)
    expect(names).to match_array(%w[bug_desk_termination no_pii bug_desk_before_model bug_desk_handoff_filer])
    expect(logger).to have_received(:warn).with(/mystery_task/)

    only_termination = registry.workers_for(agent, required_workers: ['bug_desk_termination']).map(&:task_definition_name)
    expect(only_termination).to eq(['bug_desk_termination'])
    expect(registry.workers_for(agent, required_workers: nil).size).to eq(4)
  end

  it 'collects tools from the whole team once and applies the run domain for stateful trees' do
    triage = a::Agent.new(name: 'triage', model: 'm/x')
    filer = a::Agent.new(name: 'filer', model: 'm/x', stateful: true)
    filer.add_tool :create_issue
    triage.add_tool :create_issue
    team = a::Agent.new(name: 'team', agents: [triage, filer])
    workers = registry.workers_for(team, domain: 'run-1')
    expect(workers.map(&:task_definition_name)).to eq(['create_issue'])
    expect(workers.first.domain).to eq('run-1')
  end
end
