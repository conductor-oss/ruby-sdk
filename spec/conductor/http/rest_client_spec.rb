# frozen_string_literal: true

require 'spec_helper'

# Pins the Faraday retry configuration, specifically that a reset connection is
# retried.
#
# faraday-retry's DEFAULT_EXCEPTIONS is [Errno::ETIMEDOUT, 'Timeout::Error',
# Faraday::TimeoutError, Faraday::RetriableResponse] -- no
# Faraday::ConnectionFailed. The net_http_persistent adapter raises exactly that
# for Errno::ECONNRESET (see NET_HTTP_EXCEPTIONS in
# faraday/adapter/net_http_persistent.rb), so before `exceptions:` was passed
# explicitly a reset socket became a hard ApiError with no retry at all. That is
# what failed the cloud integration job on run 34265187276 attempt 1, in
# metadata_client.register_task_def -- a POST, which net-http-persistent will
# not retry internally the way it does idempotent verbs.
RSpec.describe Conductor::Http::RestClient do
  subject(:client) { described_class.new }

  let(:retry_options) do
    handler = client.connection.builder.handlers.find { |h| h.klass == Faraday::Retry::Middleware }
    handler.instance_variable_get(:@args).first
  end

  describe 'retry configuration' do
    it 'retries Faraday::ConnectionFailed on top of the faraday-retry defaults' do
      expect(retry_options[:exceptions]).to include(Faraday::ConnectionFailed)
      expect(retry_options[:exceptions]).to include(*Faraday::Retry::Middleware::DEFAULT_EXCEPTIONS)
    end

    it 'retries POST, not only idempotent verbs' do
      expect(retry_options[:methods]).to include(:post)
    end

    it 'does not retry client errors' do
      expect(retry_options[:retry_statuses]).not_to include(400, 401, 403, 404, 405)
    end
  end

  describe 'a reset connection' do
    before do
      # The middleware's own backoff would make this take 3.5s of real time.
      allow_any_instance_of(Faraday::Retry::Middleware).to receive(:sleep)
    end

    it 'is retried, then surfaces as an ApiError once the retries are exhausted' do
      attempts = 0
      allow_any_instance_of(Net::HTTP::Persistent).to receive(:request) do
        attempts += 1
        raise Errno::ECONNRESET, 'Connection reset by peer'
      end

      expect { client.post('http://conductor.invalid/api/metadata/taskdefs', body: { 'name' => 'x' }) }
        .to raise_error(Conductor::ApiError) { |e| expect(e.status).to eq(0) }

      # Initial attempt plus max: 3. Without `exceptions:` this is 1.
      expect(attempts).to eq(4)
    end
  end
end
