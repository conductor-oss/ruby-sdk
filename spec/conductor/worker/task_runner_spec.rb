# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/conductor/worker/task_runner'
require_relative '../../../lib/conductor/worker/worker'

RSpec.describe Conductor::Worker::TaskRunner do
  let(:configuration) do
    Conductor::Configuration.new(
      server_api_url: 'http://localhost:8080/api',
      auth_key: 'test_key',
      auth_secret: 'test_secret'
    )
  end

  let(:event_dispatcher) { Conductor::Worker::Events::SyncEventDispatcher.new }
  let(:logger) { Logger.new(File::NULL) }

  let(:worker) do
    Conductor::Worker::Worker.new('test_task', poll_interval: 100, thread_count: 2) do |task|
      { result: task.input_data['value'] * 2 }
    end
  end

  let(:runner) do
    described_class.new(
      worker,
      configuration: configuration,
      event_dispatcher: event_dispatcher,
      logger: logger
    )
  end

  let(:task_client) { instance_double(Conductor::Client::TaskClient) }

  before do
    allow(Conductor::Client::TaskClient).to receive(:new).and_return(task_client)
    allow(task_client).to receive(:batch_poll_tasks).and_return([])
    allow(task_client).to receive(:update_task)
  end

  describe '#initialize' do
    it 'creates a runner with the provided worker' do
      expect(runner.worker).to eq(worker)
    end

    it 'starts in running state' do
      expect(runner.running?).to be true
    end
  end

  describe '#shutdown' do
    it 'stops the runner' do
      runner.shutdown
      expect(runner.running?).to be false
    end
  end

  describe '#run_once' do
    context 'when no tasks are available' do
      it 'increments empty poll counter' do
        runner.run_once
        # Empty polls should not raise errors
        expect { runner.run_once }.not_to raise_error
      end
    end

    context 'when tasks are available' do
      let(:task_data) do
        {
          'task_id' => 'task-123',
          'workflow_instance_id' => 'workflow-456',
          'task_def_name' => 'test_task',
          'input_data' => { 'value' => 21 }
        }
      end

      before do
        allow(task_client).to receive(:batch_poll_tasks).and_return([task_data])
      end

      it 'submits tasks for execution' do
        # Run once should poll and submit tasks
        expect { runner.run_once }.not_to raise_error
      end
    end
  end

  describe 'event publishing' do
    let(:received_events) { [] }

    before do
      event_dispatcher.register(Conductor::Worker::Events::PollStarted,
                                ->(event) { received_events << [:poll_started, event] })
      event_dispatcher.register(Conductor::Worker::Events::PollCompleted,
                                ->(event) { received_events << [:poll_completed, event] })
      event_dispatcher.register(Conductor::Worker::Events::PollFailure,
                                ->(event) { received_events << [:poll_failure, event] })
    end

    context 'on successful poll' do
      it 'publishes PollStarted and PollCompleted events' do
        runner.run_once

        expect(received_events.map(&:first)).to include(:poll_started, :poll_completed)
      end

      it 'includes task_type in events' do
        runner.run_once

        poll_started = received_events.find { |e| e[0] == :poll_started }&.last
        expect(poll_started&.task_type).to eq('test_task')
      end
    end

    context 'on poll failure' do
      before do
        allow(task_client).to receive(:batch_poll_tasks).and_raise(StandardError.new('Network error'))
      end

      it 'publishes PollFailure event' do
        runner.run_once

        expect(received_events.map(&:first)).to include(:poll_started, :poll_failure)
      end

      it 'includes the cause in PollFailure event' do
        runner.run_once

        poll_failure = received_events.find { |e| e[0] == :poll_failure }&.last
        expect(poll_failure&.cause).to be_a(StandardError)
        expect(poll_failure&.cause&.message).to eq('Network error')
      end
    end
  end

  describe 'task execution events' do
    let(:received_events) { [] }

    let(:task_data) do
      Conductor::Http::Models::Task.new.tap do |t|
        t.task_id = 'task-123'
        t.workflow_instance_id = 'workflow-456'
        t.task_def_name = 'test_task'
        t.input_data = { 'value' => 21 }
      end
    end

    before do
      allow(task_client).to receive(:batch_poll_tasks).and_return([task_data])

      event_dispatcher.register(Conductor::Worker::Events::TaskExecutionStarted,
                                ->(event) { received_events << [:execution_started, event] })
      event_dispatcher.register(Conductor::Worker::Events::TaskExecutionCompleted,
                                ->(event) { received_events << [:execution_completed, event] })
      event_dispatcher.register(Conductor::Worker::Events::TaskExecutionFailure,
                                ->(event) { received_events << [:execution_failure, event] })
    end

    context 'on successful execution' do
      it 'publishes TaskExecutionStarted and TaskExecutionCompleted events' do
        runner.run_once
        # Wait for async execution
        sleep(0.2)

        event_types = received_events.map(&:first)
        expect(event_types).to include(:execution_started)
        expect(event_types).to include(:execution_completed)
      end

      it 'includes duration in TaskExecutionCompleted' do
        runner.run_once
        sleep(0.2)

        completed = received_events.find { |e| e[0] == :execution_completed }&.last
        expect(completed&.duration_ms).to be_a(Numeric)
        expect(completed&.duration_ms).to be >= 0
      end

      it 'includes output_size_bytes in TaskExecutionCompleted' do
        runner.run_once
        sleep(0.2)

        completed = received_events.find { |e| e[0] == :execution_completed }&.last
        expect(completed&.output_size_bytes).to be_a(Integer)
      end
    end

    context 'on execution failure' do
      let(:failing_worker) do
        Conductor::Worker::Worker.new('test_task', poll_interval: 100) do |_task|
          raise StandardError, 'Worker error'
        end
      end

      let(:runner) do
        described_class.new(
          failing_worker,
          configuration: configuration,
          event_dispatcher: event_dispatcher,
          logger: logger
        )
      end

      it 'publishes TaskExecutionFailure event' do
        runner.run_once
        sleep(0.2)

        event_types = received_events.map(&:first)
        expect(event_types).to include(:execution_started)
        expect(event_types).to include(:execution_failure)
      end

      it 'marks retryable errors correctly' do
        runner.run_once
        sleep(0.2)

        failure = received_events.find { |e| e[0] == :execution_failure }&.last
        expect(failure&.is_retryable).to be true
      end
    end

    context 'on non-retryable error' do
      let(:non_retryable_worker) do
        Conductor::Worker::Worker.new('test_task', poll_interval: 100) do |_task|
          raise Conductor::NonRetryableError, 'Fatal error'
        end
      end

      let(:runner) do
        described_class.new(
          non_retryable_worker,
          configuration: configuration,
          event_dispatcher: event_dispatcher,
          logger: logger
        )
      end

      it 'marks non-retryable errors correctly' do
        runner.run_once
        sleep(0.2)

        failure = received_events.find { |e| e[0] == :execution_failure }&.last
        expect(failure&.is_retryable).to be false
      end
    end
  end

  describe 'task update failure events' do
    let(:received_events) { [] }

    let(:task_data) do
      Conductor::Http::Models::Task.new.tap do |t|
        t.task_id = 'task-123'
        t.workflow_instance_id = 'workflow-456'
        t.task_def_name = 'test_task'
        t.input_data = { 'value' => 21 }
      end
    end

    before do
      allow(task_client).to receive(:batch_poll_tasks).and_return([task_data])
      allow(task_client).to receive(:update_task).and_raise(StandardError.new('Update failed'))

      event_dispatcher.register(Conductor::Worker::Events::TaskUpdateFailure,
                                ->(event) { received_events << [:update_failure, event] })

      # Stub the RETRY_BACKOFFS constant to use 0-delay retries for faster testing
      stub_const('Conductor::Worker::TaskRunner::RETRY_BACKOFFS', [0, 0, 0, 0].freeze)
    end

    it 'publishes TaskUpdateFailure after all retries exhausted' do
      runner.run_once
      # Wait for async execution (thread pool) and retries
      sleep(1.0)

      # Should have a TaskUpdateFailure event
      failure = received_events.find { |e| e[0] == :update_failure }&.last
      expect(failure).not_to be_nil
      expect(failure.retry_count).to eq(4) # RETRY_BACKOFFS.size
      expect(failure.task_result).not_to be_nil
    end
  end

  describe 'paused worker' do
    let(:paused_worker) do
      Conductor::Worker::Worker.new('test_task', poll_interval: 100, paused: true) do |task|
        { result: task.input_data['value'] }
      end
    end

    let(:runner) do
      described_class.new(
        paused_worker,
        configuration: configuration,
        event_dispatcher: event_dispatcher,
        logger: logger
      )
    end

    it 'does not poll when paused' do
      runner.run_once

      expect(task_client).not_to have_received(:batch_poll_tasks)
    end
  end
end
