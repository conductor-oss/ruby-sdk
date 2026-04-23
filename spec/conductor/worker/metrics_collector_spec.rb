# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/conductor/worker/telemetry/metrics_collector'

# Specs follow the canonical SDK worker metric catalog defined in
# https://github.com/orkes-io/certification-cloud-util/blob/main/sdk-metrics-harmonization.md.
# Pre-existing worker-level metrics carry both `taskType` (canonical, camelCase) and
# `task_type` (Ruby-legacy, snake_case) with identical values (dual-label strategy).
# Metrics that are new to Ruby use canonical-only labels per §3.4.
RSpec.describe Conductor::Worker::Telemetry::MetricsCollector do
  let(:backend) { double('backend') }
  let(:collector) { described_class.new(backend: backend, subscribe_global_http: false) }

  before do
    allow(backend).to receive(:increment)
    allow(backend).to receive(:observe)
    allow(backend).to receive(:set)
  end

  # Canonical dual-label hash for a given task type
  def task_labels(task_type)
    { taskType: task_type, task_type: task_type }
  end

  describe '#initialize' do
    it 'uses NullBackend by default' do
      collector = described_class.new(subscribe_global_http: false)
      expect(collector.backend).to be_a(Conductor::Worker::Telemetry::NullBackend)
    end

    it 'uses NullBackend when :null is specified' do
      collector = described_class.new(backend: :null, subscribe_global_http: false)
      expect(collector.backend).to be_a(Conductor::Worker::Telemetry::NullBackend)
    end

    it 'accepts a custom backend instance' do
      custom_backend = Object.new
      collector = described_class.new(backend: custom_backend, subscribe_global_http: false)
      expect(collector.backend).to eq(custom_backend)
    end

    it 'subscribes to the global HTTP dispatcher by default' do
      Conductor::Worker::Events::GlobalDispatcher.reset!
      dispatcher = Conductor::Worker::Events::GlobalDispatcher.instance
      expect(dispatcher).to receive(:register).at_least(:once).and_call_original
      described_class.new(backend: backend)
    end
  end

  describe '#on_poll_started' do
    it 'increments task_poll_total with dual task labels' do
      event = Conductor::Worker::Events::PollStarted.new(
        task_type: 'my_task', worker_id: 'worker-1', poll_count: 5
      )
      collector.on_poll_started(event)

      expect(backend).to have_received(:increment).with(
        'task_poll_total',
        labels: task_labels('my_task')
      )
    end
  end

  describe '#on_poll_completed' do
    it 'observes task_poll_time_seconds with status=SUCCESS' do
      event = Conductor::Worker::Events::PollCompleted.new(
        task_type: 'my_task', duration_ms: 150.0, tasks_received: 3
      )
      collector.on_poll_completed(event)

      expect(backend).to have_received(:observe).with(
        'task_poll_time_seconds',
        0.15,
        labels: task_labels('my_task').merge(status: 'SUCCESS')
      )
    end
  end

  describe '#on_poll_failure' do
    it 'increments task_poll_error_total with dual `exception` + `error` labels' do
      error = StandardError.new('Connection refused')
      event = Conductor::Worker::Events::PollFailure.new(
        task_type: 'my_task', duration_ms: 100.0, cause: error
      )
      collector.on_poll_failure(event)

      expect(backend).to have_received(:increment).with(
        'task_poll_error_total',
        labels: task_labels('my_task').merge(exception: 'StandardError', error: 'StandardError')
      )
    end

    it 'also observes task_poll_time_seconds with status=FAILURE' do
      error = StandardError.new('Connection refused')
      event = Conductor::Worker::Events::PollFailure.new(
        task_type: 'my_task', duration_ms: 100.0, cause: error
      )
      collector.on_poll_failure(event)

      expect(backend).to have_received(:observe).with(
        'task_poll_time_seconds',
        0.1,
        labels: task_labels('my_task').merge(status: 'FAILURE')
      )
    end
  end

  describe '#on_task_execution_started' do
    it 'increments task_execution_started_total with canonical-only taskType label' do
      event = Conductor::Worker::Events::TaskExecutionStarted.new(
        task_type: 'my_task', task_id: 'task-123', worker_id: 'worker-1',
        workflow_instance_id: 'workflow-456'
      )
      collector.on_task_execution_started(event)

      expect(backend).to have_received(:increment).with(
        'task_execution_started_total',
        labels: { taskType: 'my_task' }
      )
    end
  end

  describe '#on_task_execution_completed' do
    let(:event) do
      Conductor::Worker::Events::TaskExecutionCompleted.new(
        task_type: 'my_task', task_id: 'task-123', worker_id: 'worker-1',
        workflow_instance_id: 'workflow-456',
        duration_ms: 500.0, output_size_bytes: 2048
      )
    end

    it 'observes task_execute_time_seconds with status=SUCCESS' do
      collector.on_task_execution_completed(event)

      expect(backend).to have_received(:observe).with(
        'task_execute_time_seconds',
        0.5,
        labels: task_labels('my_task').merge(status: 'SUCCESS')
      )
    end

    it 'sets task_result_size_bytes Gauge (canonical-only) when output_size_bytes is present' do
      collector.on_task_execution_completed(event)

      expect(backend).to have_received(:set).with(
        'task_result_size_bytes',
        2048,
        labels: { taskType: 'my_task' }
      )
    end

    it 'observes task_result_size_bytes_histogram (legacy renamed) when output_size_bytes is present' do
      collector.on_task_execution_completed(event)

      expect(backend).to have_received(:observe).with(
        'task_result_size_bytes_histogram',
        2048,
        labels: { task_type: 'my_task' }
      )
    end

    it 'skips size metrics when output_size_bytes is nil' do
      nil_event = Conductor::Worker::Events::TaskExecutionCompleted.new(
        task_type: 'my_task', task_id: 'task-123', worker_id: 'worker-1',
        workflow_instance_id: 'workflow-456',
        duration_ms: 500.0, output_size_bytes: nil
      )
      collector.on_task_execution_completed(nil_event)

      expect(backend).not_to have_received(:set).with('task_result_size_bytes', anything, anything)
      expect(backend).not_to have_received(:observe).with('task_result_size_bytes_histogram',
                                                          anything, anything)
    end
  end

  describe '#on_task_execution_failure' do
    it 'increments task_execute_error_total with dual task labels + exception + retryable' do
      error = ArgumentError.new('Invalid input')
      event = Conductor::Worker::Events::TaskExecutionFailure.new(
        task_type: 'my_task', task_id: 'task-123', worker_id: 'worker-1',
        workflow_instance_id: 'workflow-456', duration_ms: 100.0,
        cause: error, is_retryable: true
      )
      collector.on_task_execution_failure(event)

      expect(backend).to have_received(:increment).with(
        'task_execute_error_total',
        labels: task_labels('my_task').merge(exception: 'ArgumentError', retryable: 'true')
      )
    end

    it 'observes task_execute_time_seconds with status=FAILURE' do
      error = RuntimeError.new('Fatal error')
      event = Conductor::Worker::Events::TaskExecutionFailure.new(
        task_type: 'my_task', task_id: 'task-123', worker_id: 'worker-1',
        workflow_instance_id: 'workflow-456', duration_ms: 250.0,
        cause: error, is_retryable: false
      )
      collector.on_task_execution_failure(event)

      expect(backend).to have_received(:observe).with(
        'task_execute_time_seconds',
        0.25,
        labels: task_labels('my_task').merge(status: 'FAILURE')
      )
    end
  end

  describe '#on_task_update_completed' do
    it 'observes task_update_time_seconds with canonical-only labels and status=SUCCESS' do
      event = Conductor::Worker::Events::TaskUpdateCompleted.new(
        task_type: 'my_task', task_id: 'task-1', worker_id: 'w',
        workflow_instance_id: 'wf', duration_ms: 20.0
      )
      collector.on_task_update_completed(event)

      expect(backend).to have_received(:observe).with(
        'task_update_time_seconds',
        0.02,
        labels: { taskType: 'my_task', status: 'SUCCESS' }
      )
    end
  end

  describe '#on_task_update_failure' do
    let(:event) do
      Conductor::Worker::Events::TaskUpdateFailure.new(
        task_type: 'my_task', task_id: 'task-123', worker_id: 'worker-1',
        workflow_instance_id: 'workflow-456',
        cause: StandardError.new('Network error'),
        retry_count: 4, task_result: Conductor::Http::Models::TaskResult.complete,
        duration_ms: 55.0
      )
    end

    it 'increments task_update_failed_total (legacy) and task_update_error_total (canonical)' do
      collector.on_task_update_failure(event)

      expect(backend).to have_received(:increment).with(
        'task_update_failed_total',
        labels: { task_type: 'my_task' }
      )
      expect(backend).to have_received(:increment).with(
        'task_update_error_total',
        labels: task_labels('my_task').merge(exception: 'StandardError')
      )
    end

    it 'observes task_update_time_seconds with canonical-only labels and status=FAILURE when duration_ms is present' do
      collector.on_task_update_failure(event)

      expect(backend).to have_received(:observe).with(
        'task_update_time_seconds',
        0.055,
        labels: { taskType: 'my_task', status: 'FAILURE' }
      )
    end

    it 'does not emit task_update_time_seconds when duration_ms is nil' do
      no_dur_event = Conductor::Worker::Events::TaskUpdateFailure.new(
        task_type: 'my_task', task_id: 't', worker_id: 'w',
        workflow_instance_id: 'wf',
        cause: StandardError.new('x'), retry_count: 4,
        task_result: Conductor::Http::Models::TaskResult.complete,
        duration_ms: nil
      )
      collector.on_task_update_failure(no_dur_event)

      expect(backend).not_to have_received(:observe).with('task_update_time_seconds',
                                                          anything, anything)
    end
  end

  describe '#on_task_paused' do
    it 'increments task_paused_total with canonical-only taskType label' do
      event = Conductor::Worker::Events::TaskPaused.new(task_type: 'my_task')
      collector.on_task_paused(event)

      expect(backend).to have_received(:increment).with(
        'task_paused_total',
        labels: { taskType: 'my_task' }
      )
    end
  end

  describe '#on_thread_uncaught_exception' do
    it 'increments thread_uncaught_exceptions_total with exception label only' do
      event = Conductor::Worker::Events::ThreadUncaughtException.new(
        cause: RuntimeError.new('boom')
      )
      collector.on_thread_uncaught_exception(event)

      expect(backend).to have_received(:increment).with(
        'thread_uncaught_exceptions_total',
        labels: { exception: 'RuntimeError' }
      )
    end
  end

  describe '#on_active_workers_changed' do
    it 'sets active_workers Gauge with dual task labels' do
      event = Conductor::Worker::Events::ActiveWorkersChanged.new(
        task_type: 'my_task', count: 4
      )
      collector.on_active_workers_changed(event)

      expect(backend).to have_received(:set).with(
        'active_workers',
        4,
        labels: task_labels('my_task')
      )
    end
  end

  describe '#on_workflow_start_error' do
    it 'increments workflow_start_error_total with workflowType + exception' do
      event = Conductor::Worker::Events::WorkflowStartError.new(
        workflow_type: 'my_wf', cause: ArgumentError.new('bad input'), version: 1
      )
      collector.on_workflow_start_error(event)

      expect(backend).to have_received(:increment).with(
        'workflow_start_error_total',
        labels: { workflowType: 'my_wf', exception: 'ArgumentError' }
      )
    end
  end

  describe '#on_workflow_input_size' do
    it 'sets workflow_input_size_bytes Gauge with workflowType + version' do
      event = Conductor::Worker::Events::WorkflowInputSize.new(
        workflow_type: 'my_wf', size_bytes: 500, version: 1
      )
      collector.on_workflow_input_size(event)

      expect(backend).to have_received(:set).with(
        'workflow_input_size_bytes',
        500,
        labels: { workflowType: 'my_wf', version: '1' }
      )
    end

    it 'coerces a nil version to an empty string so labels are well-formed' do
      event = Conductor::Worker::Events::WorkflowInputSize.new(
        workflow_type: 'my_wf', size_bytes: 10, version: nil
      )
      collector.on_workflow_input_size(event)

      expect(backend).to have_received(:set).with(
        'workflow_input_size_bytes',
        10,
        labels: { workflowType: 'my_wf', version: '' }
      )
    end
  end

  describe '#on_http_api_request' do
    it 'observes http_api_client_request_seconds with method/uri/status labels' do
      event = Conductor::Worker::Events::HttpApiRequest.new(
        method: 'POST', uri: '/api/tasks/poll/batch/my_task',
        status: 200, duration_ms: 42.0
      )
      collector.on_http_api_request(event)

      expect(backend).to have_received(:observe).with(
        'http_api_client_request_seconds',
        0.042,
        labels: { method: 'POST', uri: '/api/tasks/poll/batch/my_task', status: '200' }
      )
    end

    it 'emits status="0" for network failures' do
      event = Conductor::Worker::Events::HttpApiRequest.new(
        method: 'GET', uri: '/api/tasks/42', status: '0', duration_ms: 500.0
      )
      collector.on_http_api_request(event)

      expect(backend).to have_received(:observe).with(
        'http_api_client_request_seconds',
        0.5,
        labels: { method: 'GET', uri: '/api/tasks/42', status: '0' }
      )
    end
  end
end

RSpec.describe Conductor::Worker::Telemetry::NullBackend do
  let(:backend) { described_class.new }

  describe '#increment' do
    it 'is a no-op' do
      expect { backend.increment('metric', labels: { foo: 'bar' }) }.not_to raise_error
    end
  end

  describe '#observe' do
    it 'is a no-op' do
      expect { backend.observe('metric', 123, labels: { foo: 'bar' }) }.not_to raise_error
    end
  end

  describe '#set' do
    it 'is a no-op' do
      expect { backend.set('metric', 456, labels: { foo: 'bar' }) }.not_to raise_error
    end
  end
end
