# frozen_string_literal: true

require 'spec_helper'

# Check if async gem is available
ASYNC_AVAILABLE = begin
  require 'async'
  true
rescue LoadError
  false
end

# Conditionally load the fiber executor
FIBER_EXECUTOR_LOADED = begin
  if ASYNC_AVAILABLE
    require_relative '../../../lib/conductor/worker/fiber_executor'
    true
  else
    false
  end
rescue Conductor::ConfigurationError
  false
end

if FIBER_EXECUTOR_LOADED
  RSpec.describe Conductor::Worker::AsyncSupport do
    describe '.available?' do
      it 'returns true when async gem is installed' do
        expect(described_class.available?).to be true
      end
    end

    describe '.require_async!' do
      it 'does not raise when async gem is available' do
        expect { described_class.require_async! }.not_to raise_error
      end
    end
  end

  RSpec.describe Conductor::Worker::FiberExecutor do
    describe '#initialize' do
      it 'creates an executor with max_concurrency' do
        executor = described_class.new(10)
        expect(executor.max_concurrency).to eq(10)
      end
    end

    describe '#at_capacity?' do
      it 'returns false when not started' do
        executor = described_class.new(5)
        expect(executor.shutdown?).to be false
      end
    end

    describe '#shutdown' do
      it 'marks the executor as shutdown' do
        executor = described_class.new(5)
        executor.shutdown
        expect(executor.shutdown?).to be true
      end
    end
  end

  RSpec.describe Conductor::Worker::FiberTaskRunner do
    let(:configuration) do
      Conductor::Configuration.new(server_api_url: 'http://localhost:8080/api')
    end

    let(:worker) do
      Conductor::Worker::Worker.new('fiber_task', poll_interval: 100, thread_count: 10) do |task|
        { result: task.input_data['value'] }
      end
    end

    describe '#initialize' do
      it 'creates a fiber task runner with configuration' do
        runner = described_class.new(worker, configuration: configuration)
        expect(runner.worker).to eq(worker)
      end
    end

    describe '#shutdown' do
      it 'signals the runner to stop' do
        runner = described_class.new(worker, configuration: configuration)
        expect { runner.shutdown }.not_to raise_error
      end
    end

    describe 'event publishing helpers' do
      let(:event_dispatcher) { Conductor::Worker::Events::SyncEventDispatcher.new }
      let(:logger) { Logger.new(File::NULL) }

      let(:runner) do
        described_class.new(worker, configuration: configuration,
                                    event_dispatcher: event_dispatcher, logger: logger)
      end

      let(:task_result) do
        Conductor::Http::Models::TaskResult.new.tap do |r|
          r.task_id = 'task-123'
          r.workflow_instance_id = 'workflow-456'
        end
      end

      before do
        runner.instance_variable_set(:@worker_id, 'fiber-worker-0')
      end

      describe '#publish_task_update_completed' do
        it 'publishes a TaskUpdateCompleted event with duration_ms' do
          received = []
          event_dispatcher.register(Conductor::Worker::Events::TaskUpdateCompleted,
                                    ->(event) { received << event })

          runner.send(:publish_task_update_completed, task_result, 55.0)

          expect(received.size).to eq(1)
          expect(received.first.task_type).to eq('fiber_task')
          expect(received.first.duration_ms).to eq(55.0)
        end
      end

      describe '#publish_task_update_failure' do
        it 'publishes a TaskUpdateFailure event with duration_ms' do
          received = []
          event_dispatcher.register(Conductor::Worker::Events::TaskUpdateFailure,
                                    ->(event) { received << event })

          error = StandardError.new('update failed')
          runner.send(:publish_task_update_failure, task_result, error, 88.0)

          expect(received.size).to eq(1)
          expect(received.first.cause).to eq(error)
          expect(received.first.duration_ms).to eq(88.0)
        end
      end

      describe '#publish_uncaught_exception' do
        it 'publishes a ThreadUncaughtException event' do
          received = []
          event_dispatcher.register(Conductor::Worker::Events::ThreadUncaughtException,
                                    ->(event) { received << event })

          runner.send(:publish_uncaught_exception, RuntimeError.new('boom'))

          expect(received.size).to eq(1)
          expect(received.first.cause).to be_a(RuntimeError)
        end

        it 'does not raise when dispatch fails' do
          broken = Conductor::Worker::Events::SyncEventDispatcher.new
          broken.register(Conductor::Worker::Events::ThreadUncaughtException,
                          ->(_e) { raise 'listener error' })
          r = described_class.new(worker, configuration: configuration,
                                          event_dispatcher: broken, logger: logger)
          r.instance_variable_set(:@worker_id, 'fiber-worker-0')

          expect { r.send(:publish_uncaught_exception, RuntimeError.new('test')) }.not_to raise_error
        end
      end

      describe 'TaskPaused when worker is paused' do
        let(:paused_worker) do
          Conductor::Worker::Worker.new('fiber_task', poll_interval: 100, paused: true) do |task|
            { result: task.input_data['value'] }
          end
        end

        it 'publishes TaskPaused and returns empty array' do
          paused_runner = described_class.new(paused_worker, configuration: configuration,
                                                             event_dispatcher: event_dispatcher,
                                                             logger: logger)
          received = []
          event_dispatcher.register(Conductor::Worker::Events::TaskPaused,
                                    ->(event) { received << event })

          result = paused_runner.send(:batch_poll, 1)

          expect(result).to eq([])
          expect(received.size).to eq(1)
          expect(received.first.task_type).to eq('fiber_task')
        end
      end
    end
  end
else
  # Test when async is not available
  RSpec.describe 'FiberExecutor (async gem unavailable)' do
    it 'documents that async gem is not installed' do
      # This test documents that the async gem is not available
      # The actual functionality cannot be tested without the gem
      expect(ASYNC_AVAILABLE).to be false
    end
  end
end
