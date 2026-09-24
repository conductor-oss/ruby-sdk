# frozen_string_literal: true

require 'spec_helper'
require 'conductor/agents'

RSpec.describe Conductor::Agents::Execution do
  let(:client) { instance_double(Conductor::Client::AgentClient) }
  let(:execution) { described_class.new('EXEC_1', client: client, agent_name: 'weather') }

  it 'blocks in result until finished and exposes the answer' do
    Thread.new do
      sleep 0.05
      execution.finish(status: 'COMPLETED', output: { 'result' => 'Sunny', 'finishReason' => 'STOP' })
    end
    expect(execution.done?).to be false
    expect(execution.result(timeout: 2)).to eq('Sunny')
    expect(execution.done?).to be true
    expect(execution.finish_reason).to eq(:stop)
    expect(execution.partial_text).to eq('Sunny')
  end

  it 'times out when asked to' do
    expect { execution.result(timeout: 0.05) }.to raise_error(Timeout::Error)
  end

  it 'raises on failed executions and maps finish reasons' do
    execution.finish(status: 'FAILED', output: {}, reason: 'LLM exploded')
    expect { execution.result }.to raise_error(Conductor::Agents::Error, /LLM exploded/)
    expect(execution.finish_reason).to eq(:error)

    rejected = described_class.new('E2', client: client)
    rejected.finish(status: 'COMPLETED', output: { 'result' => nil, 'finishReason' => 'rejected', 'rejectionReason' => 'no' })
    expect(rejected.finish_reason).to eq(:rejected)
    expect(rejected.rejected?).to be true

    expect(Conductor::Agents::FinishReason.derive('COMPLETED', 'finishReason' => 'MAX_TOKENS')).to eq(:length)
    expect(Conductor::Agents::FinishReason.derive('TERMINATED', nil)).to eq(:cancelled)
    expect(Conductor::Agents::FinishReason.derive('TIMED_OUT', nil)).to eq(:timeout)
  end

  it 'pairs tool calls with their results' do
    execution.add_tool_call('get_weather', 'city' => 'Lisbon')
    execution.add_tool_result('get_weather', 'temp_c' => 21)
    expect(execution.tool_calls.size).to eq(1)
    expect(execution.tool_calls.first.arguments).to eq('city' => 'Lisbon')
    expect(execution.tool_calls.first.result).to eq('temp_c' => 21)
    expect(execution.tool_calls.first.to_s).to include('get_weather')
  end

  it 'tracks waiting and delegates control calls to the client' do
    request = instance_double(Conductor::Agents::ApprovalRequest, approve: true)
    execution.mark_waiting(request)
    expect(execution.waiting?).to be true
    expect(execution.pending).to eq(request)
    execution.approve
    execution.clear_waiting
    expect(execution.waiting?).to be false
    expect { execution.reject }.to raise_error(Conductor::Agents::Error)

    expect(client).to receive(:pause).with('EXEC_1')
    expect(client).to receive(:resume).with('EXEC_1')
    expect(client).to receive(:cancel).with('EXEC_1', reason: 'bye')
    expect(client).to receive(:stop).with('EXEC_1')
    expect(client).to receive(:signal).with('EXEC_1', 'hurry')
    execution.pause.resume.cancel(reason: 'bye').stop.signal('hurry')
  end

  it 'loads a snapshot with .find' do
    runtime = instance_double(Conductor::Agents::AgentRuntime, client: client)
    allow(client).to receive(:get_status).with('EXEC_9').and_return(
      'executionId' => 'EXEC_9', 'agentName' => 'weather', 'status' => 'COMPLETED', 'isComplete' => true,
      'output' => { 'result' => 'done!', 'finishReason' => 'STOP' }
    )
    found = described_class.find('EXEC_9', runtime: runtime)
    expect(found.done?).to be true
    expect(found.result).to eq('done!')
    expect(found.agent_name).to eq('weather')
  end

  describe 'waiting snapshots' do
    let(:pending_tool) do
      { 'taskRefName' => 'refund_approval__1', 'response_schema' => { 'type' => 'object' },
        'toolCalls' => [{ 'name' => 'refund', 'args' => { 'amount' => 49 } }] }
    end
    let(:runtime) { instance_double(Conductor::Agents::AgentRuntime, client: client) }

    before do
      allow(client).to receive(:get_status).with('EXEC_1').and_return(
        'isComplete' => false, 'isWaiting' => true, 'pendingTool' => pending_tool
      )
    end

    it 'loads an ApprovalRequest object that can approve and clear waiting state' do
      found = described_class.find('EXEC_1', runtime: runtime)
      expect(found.pending).to be_a(Conductor::Agents::ApprovalRequest)
      expect(found.pending.task_ref_name).to eq('refund_approval__1')
      expect(found.pending.tool_calls.first).to be_a(Conductor::Agents::ToolCall)
      expect(found.pending.amount).to eq(49)
      expect(found.pending.response_schema).to eq('type' => 'object')
      expect(client).to receive(:approve).with('EXEC_1')

      request = found.approve
      expect(request).to be_responded
      expect(found).not_to be_waiting
      expect(found.pending).to be_nil
    end

    it 'can reject a refreshed approval' do
      execution.refresh!
      expect(client).to receive(:reject).with('EXEC_1', 'Needs a manager')
      execution.reject('Needs a manager')
      expect(execution).not_to be_waiting
      expect(execution.pending).to be_nil
    end

    it 'clears an approval answered by another client when refreshed' do
      execution.refresh!
      allow(client).to receive(:get_status).with('EXEC_1').and_return('isComplete' => false, 'isWaiting' => false)
      execution.refresh!
      expect(execution).not_to be_waiting
      expect(execution.pending).to be_nil
    end
  end
end
