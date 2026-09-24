# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'

RSpec.describe Conductor::Http::Api::AgentResourceApi do
  let(:base) { 'http://localhost:8080/api' }
  let(:configuration) { Conductor::Configuration.new(server_api_url: base) }
  let(:api_client) { Conductor::Http::ApiClient.new(configuration: configuration) }
  let(:api) { described_class.new(api_client) }

  before { WebMock.enable! }
  after { WebMock.reset! }

  it 'POSTs the start request and returns the parsed body' do
    stub = stub_request(:post, "#{base}/agent/start")
           .with(body: hash_including('prompt' => 'hi', 'agentConfig' => hash_including('name' => 'a')))
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                      body: { executionId: 'EXEC_1', agentName: 'a', requiredWorkers: ['get_weather'] }.to_json)

    result = api.start('agentConfig' => { 'name' => 'a' }, 'prompt' => 'hi')

    expect(stub).to have_been_requested
    expect(result).to eq('executionId' => 'EXEC_1', 'agentName' => 'a', 'requiredWorkers' => ['get_weather'])
  end

  it 'POSTs deploy and compile' do
    stub_request(:post, "#{base}/agent/deploy").to_return(body: { agentName: 'a' }.to_json,
                                                          headers: { 'Content-Type' => 'application/json' })
    stub_request(:post, "#{base}/agent/compile").to_return(body: { workflowDef: {}, requiredWorkers: [] }.to_json,
                                                           headers: { 'Content-Type' => 'application/json' })
    expect(api.deploy('agentConfig' => {})).to eq('agentName' => 'a')
    expect(api.compile('agentConfig' => {})).to include('workflowDef')
  end

  it 'GETs status and execution' do
    stub_request(:get, "#{base}/agent/EXEC_1/status")
      .to_return(body: { executionId: 'EXEC_1', isComplete: true, isWaiting: false }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, "#{base}/agent/execution/EXEC_1")
      .to_return(body: { tokenUsage: { totalTokens: 5 } }.to_json, headers: { 'Content-Type' => 'application/json' })

    expect(api.status('EXEC_1')).to include('isComplete' => true)
    expect(api.execution('EXEC_1')).to eq('tokenUsage' => { 'totalTokens' => 5 })
  end

  it 'GETs executions with query params' do
    stub = stub_request(:get, "#{base}/agent/executions").with(query: { 'size' => '5', 'agentName' => 'a' })
                                                         .to_return(body: { totalHits: 0, results: [] }.to_json,
                                                                    headers: { 'Content-Type' => 'application/json' })
    expect(api.executions(size: 5, agentName: 'a')).to eq('totalHits' => 0, 'results' => [])
    expect(stub).to have_been_requested
  end

  it 'POSTs respond, stop and signal with the exact bodies' do
    respond = stub_request(:post, "#{base}/agent/EXEC_1/respond").with(body: { approved: false, reason: 'no' }.to_json)
    stop = stub_request(:post, "#{base}/agent/EXEC_1/stop")
    signal = stub_request(:post, "#{base}/agent/EXEC_1/signal").with(body: { message: 'hurry' }.to_json)

    api.respond('EXEC_1', { 'approved' => false, 'reason' => 'no' })
    api.stop('EXEC_1')
    api.signal('EXEC_1', 'hurry')

    expect(respond).to have_been_requested
    expect(stop).to have_been_requested
    expect(signal).to have_been_requested
  end

  it 'PUTs pause/resume and DELETEs cancel with a reason' do
    pause = stub_request(:put, "#{base}/agent/EXEC_1/pause")
    resume = stub_request(:put, "#{base}/agent/EXEC_1/resume")
    cancel = stub_request(:delete, "#{base}/agent/EXEC_1/cancel").with(query: { 'reason' => 'bye' })

    api.pause('EXEC_1')
    api.resume('EXEC_1')
    api.cancel('EXEC_1', reason: 'bye')

    expect(pause).to have_been_requested
    expect(resume).to have_been_requested
    expect(cancel).to have_been_requested
  end

  it 'lists, gets and deletes deployed agents' do
    stub_request(:get, "#{base}/agent/list").to_return(body: [{ name: 'a' }].to_json,
                                                       headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, "#{base}/agent/a").with(query: { 'version' => '2' })
                                         .to_return(body: { name: 'a' }.to_json,
                                                    headers: { 'Content-Type' => 'application/json' })
    del = stub_request(:delete, "#{base}/agent/a")

    expect(api.list).to eq([{ 'name' => 'a' }])
    expect(api.get_agent('a', version: 2)).to eq('name' => 'a')
    api.delete('a')
    expect(del).to have_been_requested
  end
end
