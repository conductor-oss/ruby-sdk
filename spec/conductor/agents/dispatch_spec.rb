# frozen_string_literal: true

require 'spec_helper'
require 'support/agent_tools'

RSpec.describe Conductor::Agents::Dispatch do
  # Poll body recorded in conductor-mocks agent/tool_happy_path
  let(:recorded_input) do
    { '_agent_tool_name' => 'get_weather', '_agent_state' => {}, 'method' => 'get_weather',
      'city' => 'Lisbon', 'units' => 'metric' }
  end

  def task_with(input, runtime_metadata: {})
    Conductor::Http::Models::Task.from_hash('taskId' => 'TASK_1', 'workflowInstanceId' => 'EXEC_1',
                                            'taskType' => 'get_weather', 'inputData' => input,
                                            'runtimeMetadata' => runtime_metadata)
  end

  def with_context(task)
    result = Conductor::Http::Models::TaskResult.new
    Conductor::Worker::TaskContext.current = Conductor::Worker::TaskContext.new(task, result)
    yield
  ensure
    Conductor::Worker::TaskContext.clear
  end

  it 'strips the injected keys and runs the tool with keyword arguments' do
    result = described_class.run_tool_task(task_with(recorded_input), SpecTools::Weather[:current])
    expect(result.status).to eq('COMPLETED')
    expect(result.worker_id).to eq('agent-sdk')
    expect(result.task_id).to eq('TASK_1')
    expect(result.workflow_instance_id).to eq('EXEC_1')
    expect(result.output_data).to eq('temp_c' => 21.0, 'summary' => 'Sunny in Lisbon (metric)')
  end

  it 'fails terminally when a required argument is missing' do
    result = described_class.run_tool_task(task_with({ 'units' => 'metric' }), SpecTools::Weather[:current])
    expect(result.status).to eq('FAILED_WITH_TERMINAL_ERROR')
    expect(result.reason_for_incompletion).to include('city')
  end

  it 'coerces strings to the schema types and JSON to strings' do
    td = SpecTools::Weather[:forecast]
    input = { 'city' => 'Porto', 'days' => '5', 'detailed' => 'yes', 'tags' => '["a","b"]', 'ratio' => '0.25',
              'opts' => '{"k":1}', 'mode' => 'full' }
    result = described_class.run_tool_task(task_with(input), td)
    expect(result.output_data).to include('days' => 5, 'detailed' => true, 'tags' => %w[a b], 'ratio' => 0.25,
                                          'opts' => { 'k' => 1 }, 'mode' => 'full')
  end

  it 'wraps scalar results and keeps _state_updates' do
    scalar = Conductor::Agents::ToolDef.new(name: 's', func: ->(**) { 'plain' },
                                            input_schema: { 'type' => 'object', 'properties' => {} })
    expect(described_class.run_tool_task(task_with({}), scalar).output_data).to eq('result' => 'plain')

    stateful = Conductor::Agents::ToolDef.new(name: 's2', func: ->(**) { { ok: true, _state_updates: { 'n' => 1 } } },
                                              input_schema: { 'type' => 'object', 'properties' => {} })
    expect(described_class.run_tool_task(task_with({}), stateful).output_data).to eq('ok' => true, '_state_updates' => { 'n' => 1 })
  end

  it 'reports tool exceptions as retryable failures with the reason' do
    boom = Conductor::Agents::ToolDef.new(name: 'boom', func: ->(**) { raise 'kaput' },
                                          input_schema: { 'type' => 'object', 'properties' => {} })
    result = described_class.run_tool_task(task_with({}), boom, logger: Logger.new(nil))
    expect(result.status).to eq('FAILED')
    expect(result.reason_for_incompletion).to eq('RuntimeError: kaput')
  end

  it 'fails terminally on unserializable results' do
    bad = Conductor::Agents::ToolDef.new(name: 'bad', func: ->(**) { { io: $stdout } },
                                         input_schema: { 'type' => 'object', 'properties' => {} })
    allow(JSON).to receive(:generate).and_raise(JSON::GeneratorError, 'nope')
    result = described_class.run_tool_task(task_with({}), bad)
    expect(result.status).to eq('FAILED_WITH_TERMINAL_ERROR')
  end

  it 'reads declared secrets from the task runtimeMetadata via TaskContext' do
    task = task_with({ 'title' => 'bug', 'method' => 'create_issue' }, runtime_metadata: { 'GH_TOKEN' => 'ghp_x' })
    with_context(task) do
      result = described_class.run_tool_task(task, SpecTools::Github[:create_issue])
      expect(result.status).to eq('COMPLETED')
      expect(result.output_data['token']).to eq('ghp_x')
    end
  end

  it 'falls back to ENV and fails terminally when a declared secret is missing everywhere' do
    task = task_with({ 'title' => 'bug' })
    with_context(task) do
      ENV['GH_TOKEN'] = 'from_env'
      expect(described_class.run_tool_task(task, SpecTools::Github[:create_issue]).output_data['token']).to eq('from_env')
    ensure
      ENV.delete('GH_TOKEN')
    end
    with_context(task) do
      result = described_class.run_tool_task(task, SpecTools::Github[:create_issue])
      expect(result.status).to eq('FAILED_WITH_TERMINAL_ERROR')
      expect(result.reason_for_incompletion).to include('GH_TOKEN')
    end
  end

  it 'passes unknown keys only to tools that accept **kwargs' do
    strict = Conductor::Agents::ToolDef.new(name: 'strict', func: ->(a:) { { a: a } },
                                            input_schema: { 'type' => 'object', 'properties' => { 'a' => {} } })
    expect(described_class.run_tool_task(task_with({ 'a' => 1, 'zzz' => 2 }), strict).output_data).to eq('a' => 1)
    loose = Conductor::Agents::ToolDef.new(name: 'loose', func: ->(a:, **rest) { { a: a, rest: rest } },
                                           input_schema: { 'type' => 'object', 'properties' => { 'a' => {} } })
    expect(described_class.run_tool_task(task_with({ 'a' => 1, 'zzz' => 2 }), loose).output_data).to eq('a' => 1, 'rest' => { zzz: 2 })
  end
end

RSpec.describe Conductor::Agents::Secrets do
  it 'secrets_env returns only the requested names' do
    ENV['S_A'] = '1'
    ENV['S_B'] = '2'
    expect(described_class.secrets_env('S_A', 'S_B')).to eq('S_A' => '1', 'S_B' => '2')
  ensure
    ENV.delete('S_A')
    ENV.delete('S_B')
  end

  it 'raises CredentialNotFoundError with guidance' do
    expect { described_class.secret('NOPE_NOT_SET') }.to raise_error(Conductor::Agents::CredentialNotFoundError, /conductor secrets put/)
  end
end
