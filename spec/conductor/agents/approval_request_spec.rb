# frozen_string_literal: true

require 'spec_helper'
require 'conductor/agents'

RSpec.describe Conductor::Agents::ApprovalRequest do
  let(:client) { instance_double(Conductor::Client::AgentClient) }
  let(:pending_tool) do
    { 'taskRefName' => 'support_approval_human', 'tool_name' => nil, 'parameters' => nil,
      'toolCalls' => [{ 'name' => 'issue_refund', 'args' => { 'order_id' => 'A-1029', 'amount' => 49.0 } }],
      'response_schema' => { 'type' => 'object', 'required' => ['approved'] } }
  end
  let(:request) { described_class.new('EXEC_1', pending_tool, client: client) }

  it 'reads the batch of tool calls and exposes the first one' do
    expect(request.tool_calls.map(&:name)).to eq(['issue_refund'])
    expect(request.tool_name).to eq('issue_refund')
    expect(request.arguments).to eq('order_id' => 'A-1029', 'amount' => 49.0)
    expect(request.amount).to eq(49.0)
    expect(request.order_id).to eq('A-1029')
    expect(request.respond_to?(:amount)).to be true
    expect { request.nonexistent }.to raise_error(NoMethodError)
    expect(request.task_ref_name).to eq('support_approval_human')
  end

  it 'also understands the singular tool_name/parameters shape' do
    single = described_class.new('E', { 'tool_name' => 'ask', 'parameters' => { 'q' => 1 } }, client: client)
    expect(single.tool_name).to eq('ask')
    expect(single.q).to eq(1)
  end

  it 'approves, rejects and sends messages once' do
    execution = instance_double(Conductor::Agents::Execution, clear_waiting: nil)
    req = described_class.new('EXEC_1', pending_tool, client: client, execution: execution)
    expect(client).to receive(:approve).with('EXEC_1')
    req.approve
    expect(req.responded?).to be true
    expect(execution).to have_received(:clear_waiting)
    expect { req.approve }.to raise_error(Conductor::Agents::Error, /already/)

    expect(client).to receive(:reject).with('EXEC_1', 'Needs a manager')
    described_class.new('EXEC_1', pending_tool, client: client).reject('Needs a manager')
    expect(client).to receive(:send_message).with('EXEC_1', 'hello')
    described_class.new('EXEC_1', pending_tool, client: client).send_message('hello')
  end
end
