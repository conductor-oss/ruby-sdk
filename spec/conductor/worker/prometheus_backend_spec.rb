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

      it 'pre-registers every canonical counter' do
        %i[task_poll_total task_execution_started_total task_poll_error_total
           task_execute_error_total task_update_error_total task_paused_total
           thread_uncaught_exceptions_total workflow_start_error_total].each do |name|
          expect(backend.registry.exist?(name)).to be(true), "expected #{name} to be registered"
        end
      end

      it 'pre-registers the legacy task_update_failed_total counter' do
        expect(backend.registry.exist?(:task_update_failed_total)).to be true
      end

      it 'pre-registers every canonical histogram' do
        %i[task_poll_time_seconds task_execute_time_seconds task_update_time_seconds
           http_api_client_request_seconds].each do |name|
          expect(backend.registry.exist?(name)).to be(true), "expected #{name} to be registered"
        end
      end

      it 'pre-registers the legacy task_result_size_bytes_histogram' do
        expect(backend.registry.exist?(:task_result_size_bytes_histogram)).to be true
      end

      it 'pre-registers every canonical gauge' do
        %i[task_result_size_bytes workflow_input_size_bytes active_workers].each do |name|
          expect(backend.registry.exist?(name)).to be(true), "expected #{name} to be registered"
        end
      end
    end

    describe 'metric types (canonical Prometheus shapes)' do
      it 'registers task_result_size_bytes as a Gauge' do
        expect(backend.registry.get(:task_result_size_bytes)).to be_a(Prometheus::Client::Gauge)
      end

      it 'registers task_result_size_bytes_histogram as a Histogram' do
        expect(backend.registry.get(:task_result_size_bytes_histogram))
          .to be_a(Prometheus::Client::Histogram)
      end

      it 'registers active_workers as a Gauge' do
        expect(backend.registry.get(:active_workers)).to be_a(Prometheus::Client::Gauge)
      end

      it 'registers workflow_input_size_bytes as a Gauge' do
        expect(backend.registry.get(:workflow_input_size_bytes)).to be_a(Prometheus::Client::Gauge)
      end

      it 'registers http_api_client_request_seconds as a Histogram' do
        expect(backend.registry.get(:http_api_client_request_seconds))
          .to be_a(Prometheus::Client::Histogram)
      end
    end

    describe 'label schemas' do
      # prometheus-client 4.x rejects samples whose label set does not match the
      # one declared at registration. The backend normalizes caller-supplied labels
      # before forwarding, so these tests assert the schema + the filler behavior.
      it 'declares dual taskType/task_type labels on task_poll_total' do
        counter = backend.registry.get(:task_poll_total)
        expect(counter.labels).to match_array(%i[taskType task_type])
      end

      it 'declares canonical-only taskType label on task_execution_started_total' do
        counter = backend.registry.get(:task_execution_started_total)
        expect(counter.labels).to match_array(%i[taskType])
      end

      it 'declares canonical-only taskType label on task_paused_total' do
        counter = backend.registry.get(:task_paused_total)
        expect(counter.labels).to match_array(%i[taskType])
      end

      it 'declares canonical-only taskType/status labels on task_update_time_seconds' do
        histogram = backend.registry.get(:task_update_time_seconds)
        expect(histogram.labels).to match_array(%i[taskType status])
      end

      it 'declares canonical-only taskType label on task_result_size_bytes Gauge' do
        gauge = backend.registry.get(:task_result_size_bytes)
        expect(gauge.labels).to match_array(%i[taskType])
      end

      it 'declares the status label on every *_time_seconds histogram' do
        %i[task_poll_time_seconds task_execute_time_seconds task_update_time_seconds].each do |name|
          labels = backend.registry.get(name).labels
          expect(labels).to include(:status), "expected :status in #{name} labels: #{labels}"
        end
      end

      it 'declares method/uri/status on http_api_client_request_seconds' do
        expect(backend.registry.get(:http_api_client_request_seconds).labels)
          .to match_array(%i[method uri status])
      end

      it 'declares workflowType/version on workflow_input_size_bytes' do
        expect(backend.registry.get(:workflow_input_size_bytes).labels)
          .to match_array(%i[workflowType version])
      end

      it 'declares the exception label on thread_uncaught_exceptions_total' do
        expect(backend.registry.get(:thread_uncaught_exceptions_total).labels)
          .to match_array(%i[exception])
      end
    end

    describe 'histogram buckets' do
      it 'uses the canonical time bucket set (starting at 0.001s) on time histograms' do
        buckets = backend.registry.get(:task_poll_time_seconds).instance_variable_get(:@buckets)
        # Only assert on the lower end + that the bucket list is present and well-formed
        expect(buckets).to include(0.001)
        expect(buckets.first).to be <= 0.001
      end

      it 'uses size buckets on task_result_size_bytes_histogram' do
        buckets = backend.registry.get(:task_result_size_bytes_histogram)
                         .instance_variable_get(:@buckets)
        expect(buckets).to eq(described_class::SIZE_BUCKETS)
      end
    end

    describe '#increment' do
      it 'increments a counter with the canonical dual task labels' do
        expect do
          backend.increment('task_poll_total',
                            labels: { taskType: 'my_task', task_type: 'my_task' })
        end.not_to raise_error
      end

      it 'fills missing declared labels with empty strings so partial callers do not fail' do
        # Caller omits `error`; normalize_labels should fill it with "" rather than raising.
        expect do
          backend.increment('task_poll_error_total',
                            labels: { taskType: 'my_task', task_type: 'my_task',
                                      exception: 'StandardError' })
        end.not_to raise_error
      end

      it 'silently drops unknown labels instead of raising' do
        expect do
          backend.increment('task_poll_total',
                            labels: { taskType: 'my_task', task_type: 'my_task',
                                      not_a_real_label: 'x' })
        end.not_to raise_error
      end

      it 'increments by a custom value' do
        expect do
          backend.increment('task_poll_total',
                            labels: { taskType: 'my_task', task_type: 'my_task' }, value: 5)
        end.not_to raise_error
      end
    end

    describe '#observe' do
      it 'observes a time histogram with the canonical status label' do
        expect do
          backend.observe('task_poll_time_seconds', 0.5,
                          labels: { taskType: 'my_task', task_type: 'my_task', status: 'SUCCESS' })
        end.not_to raise_error
      end

      it 'observes the legacy size histogram with only task_type' do
        expect do
          backend.observe('task_result_size_bytes_histogram', 2048,
                          labels: { task_type: 'my_task' })
        end.not_to raise_error
      end

      it 'observes the HTTP client histogram with method/uri/status' do
        expect do
          backend.observe('http_api_client_request_seconds', 0.05,
                          labels: { method: 'POST', uri: '/api/tasks/poll/batch/x',
                                    status: '200' })
        end.not_to raise_error
      end
    end

    describe '#set' do
      it 'sets the canonical task_result_size_bytes Gauge (canonical-only labels)' do
        expect do
          backend.set('task_result_size_bytes', 2048,
                      labels: { taskType: 'my_task' })
        end.not_to raise_error
      end

      it 'sets the active_workers Gauge' do
        expect do
          backend.set('active_workers', 3,
                      labels: { taskType: 'my_task', task_type: 'my_task' })
        end.not_to raise_error
      end

      it 'sets the workflow_input_size_bytes Gauge' do
        expect do
          backend.set('workflow_input_size_bytes', 512,
                      labels: { workflowType: 'my_wf', version: '1' })
        end.not_to raise_error
      end
    end

    describe 'coexistence with a shared registry' do
      it 'reuses an already-registered metric without raising AlreadyRegisteredError' do
        first = described_class.new(registry: registry)
        expect { described_class.new(registry: registry) }.not_to raise_error
        second = described_class.new(registry: registry)
        expect(second.registry.get(:task_poll_total))
          .to equal(first.registry.get(:task_poll_total))
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
  RSpec.describe 'PrometheusBackend (prometheus-client gem unavailable)' do
    it 'documents that prometheus-client gem is not installed' do
      expect(PROMETHEUS_AVAILABLE).to be false
    end
  end
end
