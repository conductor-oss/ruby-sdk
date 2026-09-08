# frozen_string_literal: true

require 'spec_helper'
require 'conductor/agents'

RSpec.describe Conductor::Agents::StatusPoller do
  let(:client) { instance_double(Conductor::Client::AgentClient) }
  let(:poller) { described_class.new(client, interval: 0) }

  it 'emits waiting once, then done' do
    allow(client).to receive(:get_status).and_return(
      { 'executionId' => 'E', 'status' => 'RUNNING', 'isComplete' => false, 'isWaiting' => false },
      { 'executionId' => 'E', 'status' => 'RUNNING', 'isComplete' => false, 'isWaiting' => true, 'pendingTool' => { 'x' => 1 } },
      { 'executionId' => 'E', 'status' => 'RUNNING', 'isComplete' => false, 'isWaiting' => true, 'pendingTool' => { 'x' => 1 } },
      { 'executionId' => 'E', 'status' => 'COMPLETED', 'isComplete' => true, 'output' => { 'result' => 'ok' } }
    )
    events = poller.each_event('E').to_a
    expect(events.map { |e| e['event'] }).to eq(%w[waiting done])
    expect(events[0]['data']['pendingTool']).to eq('x' => 1)
    expect(events[1]['data']['output']).to eq('result' => 'ok')
  end

  it 'emits error for non-completed terminal statuses' do
    allow(client).to receive(:get_status).and_return(
      'executionId' => 'E', 'status' => 'FAILED', 'isComplete' => true, 'reasonForIncompletion' => 'bad'
    )
    event = poller.each_event('E').first
    expect(event['event']).to eq('error')
    expect(event['data']['content']).to eq('bad')
    expect(event['data']['status']).to eq('FAILED')
  end
end
