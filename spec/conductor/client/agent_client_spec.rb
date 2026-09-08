# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Conductor::Client::AgentClient do
  let(:api_client) { instance_double(Conductor::Http::ApiClient) }
  let(:agent_api) { instance_double(Conductor::Http::Api::AgentResourceApi) }
  let(:client) { described_class.new(api_client) }

  before do
    allow(Conductor::Http::Api::AgentResourceApi).to receive(:new).with(api_client).and_return(agent_api)
  end

  it 'delegates start/deploy/compile' do
    expect(agent_api).to receive(:start).with({ 'prompt' => 'x' }).and_return({ 'executionId' => 'E' })
    expect(agent_api).to receive(:deploy).with({ 'agentConfig' => {} })
    expect(agent_api).to receive(:compile).with({ 'agentConfig' => {} })

    expect(client.start_agent('prompt' => 'x')).to eq('executionId' => 'E')
    client.deploy_agent('agentConfig' => {})
    client.compile_agent('agentConfig' => {})
  end

  it 'delegates status, execution and list' do
    expect(agent_api).to receive(:status).with('E')
    expect(agent_api).to receive(:execution).with('E')
    expect(agent_api).to receive(:executions).with({ size: 1 })
    client.get_status('E')
    client.get_execution('E')
    client.list_executions(size: 1)
  end

  it 'builds approval bodies like the Python client' do
    expect(agent_api).to receive(:respond).with('E', { 'approved' => true })
    expect(agent_api).to receive(:respond).with('E', { 'approved' => false, 'reason' => 'Needs a manager' })
    expect(agent_api).to receive(:respond).with('E', { 'message' => 'hello' })
    expect(agent_api).to receive(:respond).with('E', { 'output' => 42 })

    client.approve('E')
    client.reject('E', 'Needs a manager')
    client.send_message('E', 'hello')
    client.respond('E', 42)
  end

  it 'delegates control operations' do
    expect(agent_api).to receive(:stop).with('E')
    expect(agent_api).to receive(:signal).with('E', 'go')
    expect(agent_api).to receive(:pause).with('E')
    expect(agent_api).to receive(:resume).with('E')
    expect(agent_api).to receive(:cancel).with('E', reason: 'r')
    client.stop('E')
    client.signal('E', 'go')
    client.pause('E')
    client.resume('E')
    client.cancel('E', reason: 'r')
  end

  it 'maps 404 to AgentNotFoundError and other errors to AgentApiError with the server message' do
    allow(agent_api).to receive(:status).and_raise(Conductor::ApiError.new('nf', status: 404))
    expect { client.get_status('E') }.to raise_error(Conductor::AgentNotFoundError)

    body = { error: 'agentConfig.model is required', status: 400 }.to_json
    allow(agent_api).to receive(:start).and_raise(Conductor::ApiError.new('bad', status: 400, body: body))
    expect { client.start_agent({}) }.to raise_error(Conductor::AgentApiError) { |e|
      expect(e.status).to eq(400)
      expect(e.error).to eq('agentConfig.model is required')
    }
  end
end
