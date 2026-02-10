# frozen_string_literal: true

require 'spec_helper'

# Check if prometheus-client gem is available
PROMETHEUS_AVAILABLE = begin
  require 'prometheus/client'
  true
rescue LoadError
  false
end

# Conditionally load the prometheus backend
PROMETHEUS_BACKEND_LOADED = begin
  if PROMETHEUS_AVAILABLE
    require_relative '../../../lib/conductor/worker/telemetry/prometheus_backend'
    true
  else
    false
  end
rescue Conductor::ConfigurationError
  false
end

if PROMETHEUS_BACKEND_LOADED
  RSpec.describe Conductor::Worker::Telemetry::PrometheusBackend do
    # Use a fresh registry for each test to avoid metric conflicts
    let(:registry) { Prometheus::Client::Registry.new }
    let(:backend) { described_class.new(registry: registry) }

    describe '#initialize' do
      it 'creates a backend with the provided registry' do
        expect(backend.registry).to eq(registry)
      end

      it 'registers common metrics on initialization' do
        expect(backend.registry.exist?(:task_poll_total)).to be true
        expect(backend.registry.exist?(:task_poll_error_total)).to be true
        expect(backend.registry.exist?(:task_execute_error_total)).to be true
        expect(backend.registry.exist?(:task_update_failed_total)).to be true
        expect(backend.registry.exist?(:task_poll_time_seconds)).to be true
        expect(backend.registry.exist?(:task_execute_time_seconds)).to be true
        expect(backend.registry.exist?(:task_result_size_bytes)).to be true
      end
    end

    describe '#increment' do
      it 'increments a counter' do
        expect do
          backend.increment('task_poll_total', labels: { task_type: 'my_task' })
        end.not_to raise_error
      end

      it 'increments by a custom value' do
        expect do
          backend.increment('task_poll_total', labels: { task_type: 'my_task' }, value: 5)
        end.not_to raise_error
      end
    end

    describe '#observe' do
      it 'observes a histogram value' do
        expect do
          backend.observe('task_poll_time_seconds', 0.5, labels: { task_type: 'my_task' })
        end.not_to raise_error
      end

      it 'observes size metrics' do
        expect do
          backend.observe('task_result_size_bytes', 1024, labels: { task_type: 'my_task' })
        end.not_to raise_error
      end
    end

    describe '#set' do
      it 'sets a gauge value' do
        expect do
          backend.set('active_workers', 5, labels: { task_type: 'my_task' })
        end.not_to raise_error
      end
    end
  end

  RSpec.describe Conductor::Worker::Telemetry::MetricsServer do
    it 'initializes with default port' do
      server = described_class.new
      expect(server.port).to eq(9090)
    end

    it 'accepts custom port' do
      server = described_class.new(port: 9091)
      expect(server.port).to eq(9091)
    end

    # NOTE: Actually starting/stopping the server in tests can be flaky
    # due to port binding issues. These are integration tests.
  end
else
  # Test when prometheus is not available
  RSpec.describe 'PrometheusBackend (prometheus-client gem unavailable)' do
    it 'documents that prometheus-client gem is not installed' do
      # This test documents that the prometheus-client gem is not available
      # The actual functionality cannot be tested without the gem
      expect(PROMETHEUS_AVAILABLE).to be false
    end
  end
end
