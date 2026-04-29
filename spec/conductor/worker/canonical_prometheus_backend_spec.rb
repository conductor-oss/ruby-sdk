# frozen_string_literal: true

require 'spec_helper'

CANONICAL_PROMETHEUS_AVAILABLE = begin
  require 'prometheus/client'
  true
rescue LoadError
  false
end

CANONICAL_BACKEND_LOADED = begin
  if CANONICAL_PROMETHEUS_AVAILABLE
    require_relative '../../../lib/conductor/worker/telemetry/canonical_prometheus_backend'
    true
  else
    false
  end
rescue Conductor::ConfigurationError
  false
end

if CANONICAL_BACKEND_LOADED
  RSpec.describe Conductor::Worker::Telemetry::CanonicalPrometheusBackend do
    let(:registry) { Prometheus::Client::Registry.new }
    let(:backend) { described_class.new(registry: registry) }

    describe '#initialize' do
      it 'registers canonical counters' do
        backend # force lazy initialization
        %i[task_poll_total task_execution_started_total task_poll_error_total
           task_execute_error_total task_update_error_total task_paused_total
           thread_uncaught_exceptions_total workflow_start_error_total].each do |name|
          expect(registry.exist?(name)).to be(true), "Expected counter #{name} to be registered"
        end
      end

      it 'registers canonical histograms' do
        backend
        %i[task_poll_time_seconds task_execute_time_seconds task_update_time_seconds
           http_api_client_request_seconds task_result_size_bytes
           workflow_input_size_bytes].each do |name|
          expect(registry.exist?(name)).to be(true), "Expected histogram #{name} to be registered"
        end
      end

      it 'registers canonical gauges' do
        backend
        expect(registry.exist?(:active_workers)).to be true
      end
    end

    describe '#increment' do
      it 'increments a counter with camelCase labels' do
        expect do
          backend.increment('task_poll_total', labels: { taskType: 'my_task' })
        end.not_to raise_error
      end
    end

    describe '#observe' do
      it 'observes a time histogram with status label' do
        expect do
          backend.observe('task_poll_time_seconds', 0.25,
                          labels: { taskType: 'my_task', status: 'SUCCESS' })
        end.not_to raise_error
      end

      it 'observes a size histogram' do
        expect do
          backend.observe('task_result_size_bytes', 5000, labels: { taskType: 'my_task' })
        end.not_to raise_error
      end
    end

    describe '#set' do
      it 'sets a gauge value' do
        expect do
          backend.set('active_workers', 3, labels: { taskType: 'my_task' })
        end.not_to raise_error
      end
    end

    describe 'label normalization' do
      it 'fills missing declared labels with empty strings' do
        expect do
          backend.increment('task_poll_error_total', labels: { taskType: 'my_task' })
        end.not_to raise_error
      end

      it 'drops undeclared labels' do
        expect do
          backend.increment('task_poll_total', labels: { taskType: 'my_task', extra: 'nope' })
        end.not_to raise_error
      end
    end
  end
else
  RSpec.describe 'CanonicalPrometheusBackend (prometheus-client gem unavailable)' do
    it 'documents that prometheus-client gem is not installed' do
      expect(CANONICAL_PROMETHEUS_AVAILABLE).to be false
    end
  end
end
