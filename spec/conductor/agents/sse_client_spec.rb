# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'
require 'conductor/agents'

RSpec.describe Conductor::Agents::SseClient do
  let(:base) { 'http://localhost:8080/api' }
  let(:configuration) { Conductor::Configuration.new(server_api_url: base) }
  let(:api_client) { Conductor::Http::ApiClient.new(configuration: configuration) }
  let(:client) { described_class.new(api_client, logger: Logger.new(nil)) }
  let(:recorded) do
    ":connected\n\n" \
      "id:1\nevent:thinking\ndata:{\"id\":1,\"type\":\"thinking\",\"executionId\":\"EXEC_1\",\"content\":\"weather_llm__1\",\"timestamp\":0}\n\n" \
      "id:2\nevent:tool_call\ndata:{\"id\":2,\"type\":\"tool_call\",\"executionId\":\"EXEC_1\",\"toolName\":\"get_weather\",\"args\":{\"city\":\"Lisbon\"},\"timestamp\":0}\n\n" \
      "id:3\nevent:done\ndata:{\"id\":3,\"type\":\"done\",\"executionId\":\"EXEC_1\",\"output\":{\"result\":\"Sunny\",\"finishReason\":\"STOP\"},\"timestamp\":0}\n\n"
  end

  before { WebMock.enable! }
  after { WebMock.reset! }

  describe described_class::Parser do
    it 'parses frames split across chunks, comments, integer ids and multi-line data' do
      parser = described_class.new
      events = []
      parser.feed(":connected\n\nid:7\nev") { |e| events << e }
      parser.feed("ent:message\ndata:{\"a\":\n") { |e| events << e }
      parser.feed("data:1}\n\n") { |e| events << e }
      expect(events).to eq([{ 'heartbeat' => true },
                            { 'event' => 'message', 'id' => 7, 'data' => { 'a' => 1 } }])
    end

    it 'wraps non-JSON data as content and infers the event from data.type' do
      parser = described_class.new
      events = []
      parser.feed("data:plain text\n\ndata:{\"type\":\"done\"}\n\n") { |e| events << e }
      expect(events[0]).to eq('event' => nil, 'id' => nil, 'data' => { 'content' => 'plain text' })
      expect(events[1]['event']).to eq('done')
    end
  end

  it 'streams the recorded events, drops heartbeats and stops after done' do
    stub_request(:get, "#{base}/agent/stream/EXEC_1")
      .with(headers: { 'Accept' => 'text/event-stream' })
      .to_return(status: 200, headers: { 'Content-Type' => 'text/event-stream' }, body: recorded)

    events = client.each_event('EXEC_1').to_a
    expect(events.map { |e| e['event'] }).to eq(%w[thinking tool_call done])
    expect(events.map { |e| e['id'] }).to eq([1, 2, 3])
    expect(events.last['data']['output']['result']).to eq('Sunny')
  end

  it 'raises SseUnavailableError when the first connection is refused or non-200' do
    stub_request(:get, "#{base}/agent/stream/E500").to_return(status: 500)
    expect { client.each_event('E500').to_a }.to raise_error(Conductor::Agents::SseUnavailableError, /500/)

    stub_request(:get, "#{base}/agent/stream/EDOWN").to_raise(Errno::ECONNREFUSED)
    expect { client.each_event('EDOWN').to_a }.to raise_error(Conductor::Agents::SseUnavailableError)
  end

  it 'reconnects with Last-Event-ID after the stream drops before done' do
    stub_const('Conductor::Agents::SseClient::RECONNECT_DELAY', 0)
    first = "id:1\nevent:thinking\ndata:{\"content\":\"x\"}\n\n"
    rest = "id:2\nevent:done\ndata:{\"output\":{\"result\":\"ok\"}}\n\n"
    stub_request(:get, "#{base}/agent/stream/EXEC_2").with { |req| req.headers['Last-Event-Id'].nil? }
                                                     .to_return(status: 200, body: first)
    resumed = stub_request(:get, "#{base}/agent/stream/EXEC_2").with(headers: { 'Last-Event-ID' => '1' })
                                                               .to_return(status: 200, body: rest)

    events = client.each_event('EXEC_2').to_a
    expect(events.map { |e| e['event'] }).to eq(%w[thinking done])
    expect(resumed).to have_been_requested
  end

  it 'raises SseUnavailableError when only heartbeats arrive' do
    stub_const('Conductor::Agents::SseClient::HEARTBEAT_ONLY_TIMEOUT', -1)
    stub_request(:get, "#{base}/agent/stream/EXEC_3").to_return(status: 200, body: ":heartbeat\n:heartbeat\n")
    expect { client.each_event('EXEC_3').to_a }.to raise_error(Conductor::Agents::SseUnavailableError, /heartbeats/)
  end

  it 'sends the auth header when authentication is configured' do
    configuration.authentication_settings = Conductor::AuthenticationSettings.new(key_id: 'k', key_secret: 's')
    configuration.update_token('jwt-token')
    stub = stub_request(:get, "#{base}/agent/stream/EXEC_4").with(headers: { 'X-Authorization' => 'jwt-token' })
                                                            .to_return(status: 200, body: "event:done\ndata:{}\n\n")
    client.each_event('EXEC_4').to_a
    expect(stub).to have_been_requested
  end
end
