# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/conductor/worker/telemetry/metrics_collector'

RSpec.describe Conductor::Worker::Telemetry::MetricsCollector do
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

    it 'uses NullBackend when :null is specified' do
      collector = described_class.new(backend: :null)
      expect(collector.backend).to be_a(Conductor::Worker::Telemetry::NullBackend)
    end

    it 'accepts a custom backend instance' do
      custom_backend = Object.new
      collector = described_class.new(backend: custom_backend)
      expect(collector.backend).to eq(custom_backend)
    end
  end

  describe '#on_poll_started' do
    it 'increments task_poll_total counter' do
      event = Conductor::Worker::Events::PollStarted.new(
        task_type: 'my_task',
        worker_id: 'worker-1',
        poll_count: 5
      )

      collector.on_poll_started(event)

      expect(backend).to have_received(:increment).with(
        'task_poll_total',
        labels: { task_type: 'my_task' }
      )
    end
  end

  describe '#on_poll_completed' do
    it 'observes task_poll_time_seconds histogram' do
      event = Conductor::Worker::Events::PollCompleted.new(
        task_type: 'my_task',
        duration_ms: 150.0,
        tasks_received: 3
      )

      collector.on_poll_completed(event)

      expect(backend).to have_received(:observe).with(
        'task_poll_time_seconds',
        0.15,
        labels: { task_type: 'my_task' }
      )
    end
  end

  describe '#on_poll_failure' do
    it 'increments task_poll_error_total counter with error class' do
      error = StandardError.new('Connection refused')
      event = Conductor::Worker::Events::PollFailure.new(
        task_type: 'my_task',
        duration_ms: 100.0,
        cause: error
      )

      collector.on_poll_failure(event)

      expect(backend).to have_received(:increment).with(
        'task_poll_error_total',
        labels: { task_type: 'my_task', error: 'StandardError' }
      )
    end
  end

  describe '#on_task_execution_started' do
    it 'can be called without error' do
      event = Conductor::Worker::Events::TaskExecutionStarted.new(
        task_type: 'my_task',
        task_id: 'task-123',
        worker_id: 'worker-1',
        workflow_instance_id: 'workflow-456'
      )

      # Currently a no-op but should not raise
      expect { collector.on_task_execution_started(event) }.not_to raise_error
    end
  end

  describe '#on_task_execution_completed' do
    it 'observes task_execute_time_seconds histogram' do
      event = Conductor::Worker::Events::TaskExecutionCompleted.new(
        task_type: 'my_task',
        task_id: 'task-123',
        worker_id: 'worker-1',
        workflow_instance_id: 'workflow-456',
        duration_ms: 500.0,
        output_size_bytes: 2048
      )

      collector.on_task_execution_completed(event)

      expect(backend).to have_received(:observe).with(
        'task_execute_time_seconds',
        0.5,
        labels: { task_type: 'my_task' }
      )
    end

    it 'observes task_result_size_bytes when output_size_bytes is present' do
      event = Conductor::Worker::Events::TaskExecutionCompleted.new(
        task_type: 'my_task',
        task_id: 'task-123',
        worker_id: 'worker-1',
        workflow_instance_id: 'workflow-456',
        duration_ms: 500.0,
        output_size_bytes: 2048
      )

      collector.on_task_execution_completed(event)

      expect(backend).to have_received(:observe).with(
        'task_result_size_bytes',
        2048,
        labels: { task_type: 'my_task' }
      )
    end

    it 'skips task_result_size_bytes when output_size_bytes is nil' do
      event = Conductor::Worker::Events::TaskExecutionCompleted.new(
        task_type: 'my_task',
        task_id: 'task-123',
        worker_id: 'worker-1',
        workflow_instance_id: 'workflow-456',
        duration_ms: 500.0,
        output_size_bytes: nil
      )

      collector.on_task_execution_completed(event)

      expect(backend).to have_received(:observe).once # Only duration, not size
    end
  end

  describe '#on_task_execution_failure' do
    it 'increments task_execute_error_total counter with error details' do
      error = ArgumentError.new('Invalid input')
      event = Conductor::Worker::Events::TaskExecutionFailure.new(
        task_type: 'my_task',
        task_id: 'task-123',
        worker_id: 'worker-1',
        workflow_instance_id: 'workflow-456',
        duration_ms: 100.0,
        cause: error,
        is_retryable: true
      )

      collector.on_task_execution_failure(event)

      expect(backend).to have_received(:increment).with(
        'task_execute_error_total',
        labels: {
          task_type: 'my_task',
          exception: 'ArgumentError',
          retryable: 'true'
        }
      )
    end

    it 'tracks non-retryable errors' do
      error = RuntimeError.new('Fatal error')
      event = Conductor::Worker::Events::TaskExecutionFailure.new(
        task_type: 'my_task',
        task_id: 'task-123',
        worker_id: 'worker-1',
        workflow_instance_id: 'workflow-456',
        duration_ms: 100.0,
        cause: error,
        is_retryable: false
      )

      collector.on_task_execution_failure(event)

      expect(backend).to have_received(:increment).with(
        'task_execute_error_total',
        labels: {
          task_type: 'my_task',
          exception: 'RuntimeError',
          retryable: 'false'
        }
      )
    end
  end

  describe '#on_task_update_failure' do
    it 'increments task_update_failed_total counter' do
      error = StandardError.new('Network error')
      task_result = Conductor::Http::Models::TaskResult.complete
      event = Conductor::Worker::Events::TaskUpdateFailure.new(
        task_type: 'my_task',
        task_id: 'task-123',
        worker_id: 'worker-1',
        workflow_instance_id: 'workflow-456',
        cause: error,
        retry_count: 4,
        task_result: task_result
      )

      collector.on_task_update_failure(event)

      expect(backend).to have_received(:increment).with(
        'task_update_failed_total',
        labels: { task_type: 'my_task' }
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
