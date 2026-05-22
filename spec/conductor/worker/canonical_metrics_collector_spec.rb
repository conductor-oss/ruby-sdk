# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/conductor/worker/telemetry/metrics_collector'

RSpec.describe Conductor::Worker::Telemetry::CanonicalMetricsCollector do
  let(:backend) { double('backend') }
  let(:collector) { described_class.new(backend: backend, subscribe_global_http: false) }

  before do
    allow(backend).to receive(:increment)
    allow(backend).to receive(:observe)
    allow(backend).to receive(:set)
  end

  describe '#initialize' do
    it 'uses NullBackend by default' do
      c = described_class.new(subscribe_global_http: false)
      expect(c.backend).to be_a(Conductor::Worker::Telemetry::NullBackend)
    end
  end

  describe '#collector_name' do
    it 'returns "canonical"' do
      expect(collector.collector_name).to eq('canonical')
    end
  end

  # --- Task Runner Events ---

  describe '#on_poll_started' do
    it 'increments task_poll_total with camelCase taskType label' do
      event = Conductor::Worker::Events::PollStarted.new(
        task_type: 'my_task', worker_id: 'w1', poll_count: 1
      )
      collector.on_poll_started(event)
      expect(backend).to have_received(:increment).with(
        'task_poll_total', labels: { taskType: 'my_task' }
      )
    end
  end

  describe '#on_poll_completed' do
    it 'observes task_poll_time_seconds with status=SUCCESS' do
      event = Conductor::Worker::Events::PollCompleted.new(
        task_type: 'my_task', duration_ms: 250.0, tasks_received: 2
      )
      collector.on_poll_completed(event)
      expect(backend).to have_received(:observe).with(
        'task_poll_time_seconds', 0.25,
        labels: { taskType: 'my_task', status: 'SUCCESS' }
      )
    end
  end

  describe '#on_poll_failure' do
    it 'increments task_poll_error_total with exception label' do
      error = Timeout::Error.new('timed out')
      event = Conductor::Worker::Events::PollFailure.new(
        task_type: 'my_task', duration_ms: 100.0, cause: error
      )
      collector.on_poll_failure(event)
      expect(backend).to have_received(:increment).with(
        'task_poll_error_total',
        labels: { taskType: 'my_task', exception: 'Timeout::Error' }
      )
    end

    it 'observes task_poll_time_seconds with status=FAILURE' do
      error = StandardError.new('nope')
      event = Conductor::Worker::Events::PollFailure.new(
        task_type: 'my_task', duration_ms: 80.0, cause: error
      )
      collector.on_poll_failure(event)
      expect(backend).to have_received(:observe).with(
        'task_poll_time_seconds', 0.08,
        labels: { taskType: 'my_task', status: 'FAILURE' }
      )
    end
  end

  describe '#on_task_execution_started' do
    it 'increments task_execution_started_total' do
      event = Conductor::Worker::Events::TaskExecutionStarted.new(
        task_type: 'my_task', task_id: 't1', worker_id: 'w1', workflow_instance_id: 'wf1'
      )
      collector.on_task_execution_started(event)
      expect(backend).to have_received(:increment).with(
        'task_execution_started_total', labels: { taskType: 'my_task' }
      )
    end
  end

  describe '#on_task_execution_completed' do
    it 'observes task_execute_time_seconds with status=SUCCESS' do
      event = Conductor::Worker::Events::TaskExecutionCompleted.new(
        task_type: 'my_task', task_id: 't1', worker_id: 'w1',
        workflow_instance_id: 'wf1', duration_ms: 1200.0, output_size_bytes: 4096
      )
      collector.on_task_execution_completed(event)
      expect(backend).to have_received(:observe).with(
        'task_execute_time_seconds', 1.2,
        labels: { taskType: 'my_task', status: 'SUCCESS' }
      )
    end

    it 'observes task_result_size_bytes as histogram with taskType label' do
      event = Conductor::Worker::Events::TaskExecutionCompleted.new(
        task_type: 'my_task', task_id: 't1', worker_id: 'w1',
        workflow_instance_id: 'wf1', duration_ms: 500.0, output_size_bytes: 4096
      )
      collector.on_task_execution_completed(event)
      expect(backend).to have_received(:observe).with(
        'task_result_size_bytes', 4096, labels: { taskType: 'my_task' }
      )
    end

    it 'skips task_result_size_bytes when output_size_bytes is nil' do
      event = Conductor::Worker::Events::TaskExecutionCompleted.new(
        task_type: 'my_task', task_id: 't1', worker_id: 'w1',
        workflow_instance_id: 'wf1', duration_ms: 500.0
      )
      collector.on_task_execution_completed(event)
      expect(backend).to have_received(:observe).once
    end
  end

  describe '#on_task_execution_failure' do
    it 'increments task_execute_error_total and observes time with FAILURE' do
      error = ArgumentError.new('bad input')
      event = Conductor::Worker::Events::TaskExecutionFailure.new(
        task_type: 'my_task', task_id: 't1', worker_id: 'w1',
        workflow_instance_id: 'wf1', duration_ms: 300.0, cause: error, is_retryable: true
      )
      collector.on_task_execution_failure(event)

      expect(backend).to have_received(:increment).with(
        'task_execute_error_total',
        labels: { taskType: 'my_task', exception: 'ArgumentError' }
      )
      expect(backend).to have_received(:observe).with(
        'task_execute_time_seconds', 0.3,
        labels: { taskType: 'my_task', status: 'FAILURE' }
      )
    end
  end

  describe '#on_task_update_completed' do
    it 'observes task_update_time_seconds with status=SUCCESS' do
      event = Conductor::Worker::Events::TaskUpdateCompleted.new(
        task_type: 'my_task', task_id: 't1', worker_id: 'w1',
        workflow_instance_id: 'wf1', duration_ms: 75.0
      )
      collector.on_task_update_completed(event)
      expect(backend).to have_received(:observe).with(
        'task_update_time_seconds', 0.075,
        labels: { taskType: 'my_task', status: 'SUCCESS' }
      )
    end
  end

  describe '#on_task_update_failure' do
    it 'increments task_update_error_total and observes time with FAILURE' do
      error = StandardError.new('net err')
      task_result = Conductor::Http::Models::TaskResult.complete
      event = Conductor::Worker::Events::TaskUpdateFailure.new(
        task_type: 'my_task', task_id: 't1', worker_id: 'w1',
        workflow_instance_id: 'wf1', cause: error, retry_count: 4,
        task_result: task_result, duration_ms: 120.0
      )
      collector.on_task_update_failure(event)

      expect(backend).to have_received(:increment).with(
        'task_update_error_total',
        labels: { taskType: 'my_task', exception: 'StandardError' }
      )
      expect(backend).to have_received(:observe).with(
        'task_update_time_seconds', 0.12,
        labels: { taskType: 'my_task', status: 'FAILURE' }
      )
    end

    it 'skips time observation when duration_ms is nil' do
      error = StandardError.new('err')
      task_result = Conductor::Http::Models::TaskResult.complete
      event = Conductor::Worker::Events::TaskUpdateFailure.new(
        task_type: 'my_task', task_id: 't1', worker_id: 'w1',
        workflow_instance_id: 'wf1', cause: error, retry_count: 4, task_result: task_result
      )
      collector.on_task_update_failure(event)
      expect(backend).not_to have_received(:observe)
    end
  end

  describe '#on_task_paused' do
    it 'increments task_paused_total' do
      event = Conductor::Worker::Events::TaskPaused.new(task_type: 'my_task')
      collector.on_task_paused(event)
      expect(backend).to have_received(:increment).with(
        'task_paused_total', labels: { taskType: 'my_task' }
      )
    end
  end

  describe '#on_thread_uncaught_exception' do
    it 'increments thread_uncaught_exceptions_total with exception label' do
      event = Conductor::Worker::Events::ThreadUncaughtException.new(
        cause: RuntimeError.new('boom')
      )
      collector.on_thread_uncaught_exception(event)
      expect(backend).to have_received(:increment).with(
        'thread_uncaught_exceptions_total', labels: { exception: 'RuntimeError' }
      )
    end
  end

  describe '#on_active_workers_changed' do
    it 'sets active_workers gauge' do
      event = Conductor::Worker::Events::ActiveWorkersChanged.new(
        task_type: 'my_task', count: 7
      )
      collector.on_active_workers_changed(event)
      expect(backend).to have_received(:set).with(
        'active_workers', 7, labels: { taskType: 'my_task' }
      )
    end
  end

  # --- Workflow Events ---

  describe '#on_workflow_start_error' do
    it 'increments workflow_start_error_total' do
      event = Conductor::Worker::Events::WorkflowStartError.new(
        workflow_type: 'my_wf', cause: RuntimeError.new('fail')
      )
      collector.on_workflow_start_error(event)
      expect(backend).to have_received(:increment).with(
        'workflow_start_error_total',
        labels: { workflowType: 'my_wf', exception: 'RuntimeError' }
      )
    end
  end

  describe '#on_workflow_input_size' do
    it 'observes workflow_input_size_bytes' do
      event = Conductor::Worker::Events::WorkflowInputSize.new(
        workflow_type: 'my_wf', size_bytes: 8192, version: 2
      )
      collector.on_workflow_input_size(event)
      expect(backend).to have_received(:observe).with(
        'workflow_input_size_bytes', 8192,
        labels: { workflowType: 'my_wf', version: '2' }
      )
    end
  end

  # --- HTTP Events ---

  describe '#on_http_api_request' do
    it 'observes http_api_client_request_seconds' do
      event = Conductor::Worker::Events::HttpApiRequest.new(
        method: 'POST', uri: '/api/tasks/poll/batch/my_task', status: '200', duration_ms: 45.0
      )
      collector.on_http_api_request(event)
      expect(backend).to have_received(:observe).with(
        'http_api_client_request_seconds', 0.045,
        labels: { method: 'POST', uri: '/api/tasks/poll/batch/my_task', status: '200' }
      )
    end
  end
end
