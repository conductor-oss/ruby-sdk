# frozen_string_literal: true

require 'spec_helper'
require 'support/agent_tools'

RSpec.describe Conductor::Agents::AgentRuntime do
  a = Conductor::Agents
  let(:configuration) { Conductor::Configuration.new(server_api_url: 'http://localhost:8080/api') }
  let(:api_client) { instance_double(Conductor::Http::ApiClient, configuration: configuration) }
  let(:client) { instance_double(Conductor::Client::AgentClient) }
  let(:handler) { instance_double(Conductor::Worker::TaskHandler, start: nil, stop: nil) }
  let(:runtime) do
    described_class.new(configuration: configuration, agent_config: a::AgentConfig.new, logger: Logger.new(nil),
                        api_client: api_client, agent_client: client)
  end
  let(:agent) do
    ag = a::Agent.new(name: 'weather', model: 'openai/gpt-4o-mini', instructions: 'Answer weather questions.')
    ag.add_tool :current
    ag
  end
  let(:done_output) { { 'result' => 'Sunny in Lisbon, 21C.', 'finishReason' => 'STOP', 'context' => {}, 'rejectionReason' => nil } }

  def event(type, data = {})
    { 'event' => type, 'id' => 1, 'data' => { 'type' => type, 'executionId' => 'EXEC_1' }.merge(data) }
  end

  def stub_stream(*events)
    sse = instance_double(Conductor::Agents::SseClient)
    allow(Conductor::Agents::SseClient).to receive(:new).and_return(sse)
    allow(sse).to receive(:each_event) { |_id, &blk| events.each { |e| blk.call(e) } }
    sse
  end

  before do
    allow(Conductor::Worker::TaskHandler).to receive(:new).and_return(handler)
    allow(client).to receive(:get_execution).and_return('tokenUsage' => { 'promptTokens' => 196, 'completionTokens' => 50,
                                                                          'totalTokens' => 246 }, 'tasks' => [])
  end

  after { runtime.shutdown }

  describe '#call_async / #call_sync' do
    it 'starts the agent with the serialized config, registers the required workers and streams to the answer' do
      expect(client).to receive(:start_agent) do |payload|
        expect(payload['agentConfig']).to eq(a::ConfigSerializer.serialize(agent))
        expect(payload['prompt']).to eq('Weather in Lisbon?')
        expect(payload['sessionId']).to eq('')
        expect(payload['media']).to eq([])
        expect(payload).not_to have_key('runId')
        { 'executionId' => 'EXEC_1', 'agentName' => 'weather', 'requiredWorkers' => ['current'] }
      end
      expect(Conductor::Worker::TaskHandler).to receive(:new) do |workers:, **_|
        expect(workers.map(&:task_definition_name)).to eq(['current'])
        handler
      end
      stub_stream(event('thinking', 'content' => 'weather_llm__1'),
                  event('tool_call', 'toolName' => 'current', 'args' => { 'method' => 'current', '_agent_state' => {}, 'city' => 'Lisbon' }),
                  event('tool_result', 'toolName' => 'current', 'result' => { 'temp_c' => 21.0 }),
                  event('done', 'output' => done_output))

      answers = []
      execution = runtime.call_async(agent, 'Weather in Lisbon?') { |answer| answers << answer }
      expect(execution.result(timeout: 5)).to eq('Sunny in Lisbon, 21C.')
      expect(execution.finish_reason).to eq(:stop)
      expect(execution.tool_calls.first.arguments).to eq('city' => 'Lisbon')
      expect(execution.tool_calls.first.result).to eq('temp_c' => 21.0)
      expect(execution.token_usage.total_tokens).to eq(246)
      expect(runtime.running_workers).to eq(['current'])
      sleep 0.05 until execution.done? && !answers.empty?
      expect(answers).to eq(['Sunny in Lisbon, 21C.'])
    end

    it 'call_sync returns the answer and passes session_id through' do
      expect(client).to receive(:start_agent).with(hash_including('sessionId' => 'cust-77'))
                                             .and_return('executionId' => 'EXEC_1', 'requiredWorkers' => [])
      stub_stream(event('done', 'output' => done_output))
      expect(runtime.call_sync(agent, 'hi', session_id: 'cust-77', timeout: 5)).to eq('Sunny in Lisbon, 21C.')
    end

    it 'invokes on_approval with an ApprovalRequest and posts the decision' do
      support = a::Agent.new(name: 'support', model: 'anthropic/claude-sonnet-4-5')
      support.add_tool :issue_refund
      decisions = []
      support.on_approval do |req|
        decisions << req.amount
        req.amount < 100 ? req.approve : req.reject('Needs a manager')
      end

      allow(client).to receive(:start_agent).and_return('executionId' => 'EXEC_1', 'requiredWorkers' => ['issue_refund'])
      expect(client).to receive(:approve).with('EXEC_1')
      stub_stream(event('waiting', 'pendingTool' => { 'taskRefName' => 'support_approval_human',
                                                      'toolCalls' => [{ 'name' => 'issue_refund', 'args' => { 'order_id' => 'A-1029', 'amount' => 49.0 } }] }),
                  event('done', 'output' => done_output.merge('result' => 'Refunded $49.')))

      expect(runtime.call_sync(support, 'Refund order A-1029', timeout: 5)).to eq('Refunded $49.')
      expect(decisions).to eq([49.0])
    end

    it 'parks the request on execution.pending when no on_approval handler exists and reports rejection' do
      support = a::Agent.new(name: 'support', model: 'anthropic/claude-sonnet-4-5')
      allow(client).to receive(:start_agent).and_return('executionId' => 'EXEC_1', 'requiredWorkers' => [])
      gate = Queue.new
      sse = instance_double(a::SseClient)
      allow(a::SseClient).to receive(:new).and_return(sse)
      allow(sse).to receive(:each_event) do |_id, &blk|
        blk.call(event('waiting', 'pendingTool' => { 'toolCalls' => [{ 'name' => 'issue_refund', 'args' => { 'amount' => 500 } }] }))
        gate.pop
        blk.call(event('done', 'output' => { 'result' => nil, 'finishReason' => 'rejected', 'rejectionReason' => 'Needs a manager' }))
      end

      execution = runtime.call_async(support, 'Refund order A-1029')
      sleep 0.01 until execution.waiting?
      expect(execution.pending.tool_name).to eq('issue_refund')
      expect(client).to receive(:reject).with('EXEC_1', 'Needs a manager')
      execution.reject('Needs a manager')
      gate << :go
      expect(execution.result(timeout: 5)).to be_nil
      expect(execution.finish_reason).to eq(:rejected)
    end

    it 'logs and survives exceptions raised in user callbacks' do
      support = a::Agent.new(name: 'support', model: 'm/x')
      support.on_approval { |_req| raise 'user bug' }
      allow(client).to receive(:start_agent).and_return('executionId' => 'EXEC_1', 'requiredWorkers' => [])
      stub_stream(event('waiting', 'pendingTool' => { 'toolCalls' => [{ 'name' => 't', 'args' => {} }] }),
                  event('done', 'output' => done_output))
      execution = runtime.call_async(support, 'x') { |_| raise 'on_done bug' }
      expect(execution.result(timeout: 5)).to eq('Sunny in Lisbon, 21C.')
    end

    it 'delivers streaming events and isolates an event listener failure' do
      allow(client).to receive(:start_agent).and_return('executionId' => 'EXEC_1', 'requiredWorkers' => [])
      stub_stream(event('message', 'content' => 'Sunny'), event('done', 'output' => done_output))
      observed = Queue.new
      listener = lambda do |ev|
        observed << ev['event']
        raise 'display failed' if ev['event'] == 'message'
      end
      execution = runtime.call_async(agent, 'hi', on_event: listener)
      expect(execution.result(timeout: 5)).to eq('Sunny in Lisbon, 21C.')
      runtime.shutdown
      expect([observed.pop, observed.pop]).to eq(%w[message done])
    end

    it 'falls back to status polling when SSE is unavailable' do
      allow(client).to receive(:start_agent).and_return('executionId' => 'EXEC_1', 'requiredWorkers' => [])
      sse = instance_double(a::SseClient)
      allow(a::SseClient).to receive(:new).and_return(sse)
      allow(sse).to receive(:each_event).and_raise(a::SseUnavailableError, 'no sse')
      allow(client).to receive(:get_status).and_return('executionId' => 'EXEC_1', 'status' => 'COMPLETED',
                                                       'isComplete' => true, 'output' => done_output)
      expect(runtime.call_sync(agent, 'hi', timeout: 5)).to eq('Sunny in Lisbon, 21C.')
    end

    it 'uses polling when streaming is disabled and surfaces server errors' do
      quiet = described_class.new(configuration: configuration, agent_config: a::AgentConfig.new(streaming_enabled: false),
                                  logger: Logger.new(nil), api_client: api_client, agent_client: client)
      allow(client).to receive(:start_agent).and_return('executionId' => 'EXEC_1', 'requiredWorkers' => [])
      allow(client).to receive(:get_status).and_return('executionId' => 'EXEC_1', 'status' => 'FAILED', 'isComplete' => true,
                                                       'reasonForIncompletion' => 'model quota exceeded')
      expect { quiet.call_sync(agent, 'hi', timeout: 5) }.to raise_error(a::Error, /model quota exceeded/)
      quiet.shutdown
    end

    it 'sends a runId and uses it as the worker domain for stateful agents' do
      stateful = a::Agent.new(name: 'notes', model: 'm/x', stateful: true)
      stateful.add_tool :current
      expect(client).to receive(:start_agent) do |payload|
        expect(payload['runId']).to match(/\A[0-9a-f]{32}\z/)
        { 'executionId' => 'EXEC_1', 'requiredWorkers' => ['current'] }
      end
      expect(Conductor::Worker::TaskHandler).to receive(:new) do |workers:, **_|
        expect(workers.first.domain).to match(/\A[0-9a-f]{32}\z/)
        handler
      end
      stub_stream(event('done', 'output' => done_output))
      runtime.call_sync(stateful, 'remember this', timeout: 5)
    end

    it 'does not start a second handler for workers that are already polling' do
      allow(client).to receive(:start_agent).and_return('executionId' => 'EXEC_1', 'requiredWorkers' => ['current'])
      stub_stream(event('done', 'output' => done_output))
      runtime.call_sync(agent, 'a', timeout: 5)
      runtime.call_sync(agent, 'b', timeout: 5)
      expect(Conductor::Worker::TaskHandler).to have_received(:new).once
    end
  end

  describe '#deploy / #compile / #serve' do
    it 'deploys each agent and returns the names' do
      expect(client).to receive(:deploy_agent).with(hash_including('agentConfig' => hash_including('name' => 'weather')))
                                              .and_return('agentName' => 'weather', 'requiredWorkers' => ['current'])
      expect(runtime.deploy(agent)).to eq(['weather'])
    end

    it 'compiles without registering' do
      expect(client).to receive(:compile_agent).and_return('workflowDef' => {}, 'requiredWorkers' => [])
      expect(runtime.compile(agent)).to include('workflowDef')
    end

    it 'serve deploys and starts workers without blocking when asked' do
      allow(client).to receive(:deploy_agent).and_return('agentName' => 'weather', 'requiredWorkers' => ['current'])
      runtime.serve(agent, blocking: false)
      expect(runtime.running_workers).to eq(['current'])
    end
  end

  describe '#shutdown' do
    it 'stops handlers and forgets running workers' do
      allow(client).to receive(:deploy_agent).and_return('agentName' => 'weather', 'requiredWorkers' => ['current'])
      runtime.serve(agent, blocking: false)
      runtime.shutdown
      expect(handler).to have_received(:stop)
      expect(runtime.running_workers).to eq([])
    end
  end
end

RSpec.describe Conductor::Agents, '.runtime' do
  after { described_class.shutdown }

  it 'memoizes a default runtime and can be reconfigured' do
    allow(Conductor::Http::ApiClient).to receive(:new).and_return(instance_double(Conductor::Http::ApiClient))
    first = described_class.runtime
    expect(described_class.runtime).to equal(first)
    reconfigured = described_class.configure(configuration: Conductor::Configuration.new(server_api_url: 'http://x/api'))
    expect(reconfigured).not_to equal(first)
    expect(described_class.runtime).to equal(reconfigured)
  end
end
