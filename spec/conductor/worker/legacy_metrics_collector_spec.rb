# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/conductor/worker/telemetry/metrics_collector'

RSpec.describe Conductor::Worker::Telemetry::LegacyMetricsCollector do
  let(:backend) { double('backend') }
  let(:collector) { described_class.new(backend: backend) }

  before do
    allow(backend).to receive(:increment)
    allow(backend).to receive(:observe)
    allow(backend).to receive(:set)
  end

  describe '#initialize' do
    it 'uses NullBackend by default' do
      collector = described_class.new
      expect(collector.backend).to be_a(Conductor::Worker::Telemetry::NullBackend)
    end

    it 'accepts a custom backend instance' do
      custom = Object.new
      collector = described_class.new(backend: custom)
      expect(collector.backend).to eq(custom)
    end
  end

  describe '#on_poll_started' do
    it 'increments task_poll_total with snake_case task_type' do
      event = Conductor::Worker::Events::PollStarted.new(
        task_type: 'my_task', worker_id: 'w1', poll_count: 1
      )
      collector.on_poll_started(event)
      expect(backend).to have_received(:increment).with(
        'task_poll_total', labels: { task_type: 'my_task' }
      )
    end
  end

  describe '#on_poll_completed' do
    it 'observes task_poll_time_seconds without status label' do
      event = Conductor::Worker::Events::PollCompleted.new(
        task_type: 'my_task', duration_ms: 150.0, tasks_received: 3
      )
      collector.on_poll_completed(event)
      expect(backend).to have_received(:observe).with(
        'task_poll_time_seconds', 0.15, labels: { task_type: 'my_task' }
      )
    end
  end

  describe '#on_poll_failure' do
    it 'increments task_poll_error_total with error label' do
      error = StandardError.new('timeout')
      event = Conductor::Worker::Events::PollFailure.new(
        task_type: 'my_task', duration_ms: 100.0, cause: error
      )
      collector.on_poll_failure(event)
      expect(backend).to have_received(:increment).with(
        'task_poll_error_total', labels: { task_type: 'my_task', error: 'StandardError' }
      )
    end
  end

  describe '#on_task_execution_started' do
    it 'is a no-op (no legacy metric)' do
      event = Conductor::Worker::Events::TaskExecutionStarted.new(
        task_type: 'my_task', task_id: 't1', worker_id: 'w1', workflow_instance_id: 'wf1'
      )
      expect { collector.on_task_execution_started(event) }.not_to raise_error
      expect(backend).not_to have_received(:increment)
    end
  end

  describe '#on_task_execution_completed' do
    it 'observes task_execute_time_seconds' do
      event = Conductor::Worker::Events::TaskExecutionCompleted.new(
        task_type: 'my_task', task_id: 't1', worker_id: 'w1',
        workflow_instance_id: 'wf1', duration_ms: 500.0, output_size_bytes: 2048
      )
      collector.on_task_execution_completed(event)
      expect(backend).to have_received(:observe).with(
        'task_execute_time_seconds', 0.5, labels: { task_type: 'my_task' }
      )
    end

    it 'observes task_result_size_bytes when output_size_bytes is present' do
      event = Conductor::Worker::Events::TaskExecutionCompleted.new(
        task_type: 'my_task', task_id: 't1', worker_id: 'w1',
        workflow_instance_id: 'wf1', duration_ms: 500.0, output_size_bytes: 2048
      )
      collector.on_task_execution_completed(event)
      expect(backend).to have_received(:observe).with(
        'task_result_size_bytes', 2048, labels: { task_type: 'my_task' }
      )
    end

    it 'skips task_result_size_bytes when output_size_bytes is nil' do
      event = Conductor::Worker::Events::TaskExecutionCompleted.new(
        task_type: 'my_task', task_id: 't1', worker_id: 'w1',
        workflow_instance_id: 'wf1', duration_ms: 500.0, output_size_bytes: nil
      )
      collector.on_task_execution_completed(event)
      expect(backend).to have_received(:observe).once
    end
  end

  describe '#on_task_execution_failure' do
    it 'increments task_execute_error_total with exception and retryable labels' do
      error = ArgumentError.new('bad')
      event = Conductor::Worker::Events::TaskExecutionFailure.new(
        task_type: 'my_task', task_id: 't1', worker_id: 'w1',
        workflow_instance_id: 'wf1', duration_ms: 100.0, cause: error, is_retryable: true
      )
      collector.on_task_execution_failure(event)
      expect(backend).to have_received(:increment).with(
        'task_execute_error_total',
        labels: { task_type: 'my_task', exception: 'ArgumentError', retryable: 'true' }
      )
    end
  end

  describe '#on_task_update_failure' do
    it 'increments task_update_failed_total' do
      error = StandardError.new('net error')
      task_result = Conductor::Http::Models::TaskResult.complete
      event = Conductor::Worker::Events::TaskUpdateFailure.new(
        task_type: 'my_task', task_id: 't1', worker_id: 'w1',
        workflow_instance_id: 'wf1', cause: error, retry_count: 4, task_result: task_result
      )
      collector.on_task_update_failure(event)
      expect(backend).to have_received(:increment).with(
        'task_update_failed_total', labels: { task_type: 'my_task' }
      )
    end
  end

  # Canonical-only events should be no-ops
  describe 'canonical-only stubs' do
    it 'does not raise on on_task_update_completed' do
      event = Conductor::Worker::Events::TaskUpdateCompleted.new(
        task_type: 'my_task', task_id: 't1', worker_id: 'w1',
        workflow_instance_id: 'wf1', duration_ms: 50.0
      )
      expect { collector.on_task_update_completed(event) }.not_to raise_error
      expect(backend).not_to have_received(:observe)
    end

    it 'does not raise on on_task_paused' do
      event = Conductor::Worker::Events::TaskPaused.new(task_type: 'my_task')
      expect { collector.on_task_paused(event) }.not_to raise_error
    end

    it 'does not raise on on_thread_uncaught_exception' do
      event = Conductor::Worker::Events::ThreadUncaughtException.new(cause: RuntimeError.new('boom'))
      expect { collector.on_thread_uncaught_exception(event) }.not_to raise_error
    end

    it 'does not raise on on_active_workers_changed' do
      event = Conductor::Worker::Events::ActiveWorkersChanged.new(task_type: 'my_task', count: 3)
      expect { collector.on_active_workers_changed(event) }.not_to raise_error
    end

    it 'does not raise on on_workflow_start_error' do
      event = Conductor::Worker::Events::WorkflowStartError.new(
        workflow_type: 'my_wf', cause: RuntimeError.new('fail')
      )
      expect { collector.on_workflow_start_error(event) }.not_to raise_error
    end

    it 'does not raise on on_workflow_input_size' do
      event = Conductor::Worker::Events::WorkflowInputSize.new(
        workflow_type: 'my_wf', size_bytes: 1024
      )
      expect { collector.on_workflow_input_size(event) }.not_to raise_error
    end

    it 'does not raise on on_http_api_request' do
      event = Conductor::Worker::Events::HttpApiRequest.new(
        method: 'GET', uri: '/api/tasks', status: '200', duration_ms: 50.0
      )
      expect { collector.on_http_api_request(event) }.not_to raise_error
    end
  end
end
