# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Conductor::Worker::Events do
  describe Conductor::Worker::Events::SyncEventDispatcher do
    let(:dispatcher) { described_class.new }

    describe '#register' do
      it 'registers a listener for an event type' do
        listener = ->(event) { event }
        dispatcher.register(Conductor::Worker::Events::PollStarted, listener)

        expect(dispatcher.has_listeners?(Conductor::Worker::Events::PollStarted)).to be true
        expect(dispatcher.listener_count(Conductor::Worker::Events::PollStarted)).to eq(1)
      end

      it 'does not register duplicate listeners' do
        listener = ->(event) { event }
        dispatcher.register(Conductor::Worker::Events::PollStarted, listener)
        dispatcher.register(Conductor::Worker::Events::PollStarted, listener)

        expect(dispatcher.listener_count(Conductor::Worker::Events::PollStarted)).to eq(1)
      end
    end

    describe '#unregister' do
      it 'removes a listener' do
        listener = ->(event) { event }
        dispatcher.register(Conductor::Worker::Events::PollStarted, listener)
        dispatcher.unregister(Conductor::Worker::Events::PollStarted, listener)

        expect(dispatcher.has_listeners?(Conductor::Worker::Events::PollStarted)).to be false
      end
    end

    describe '#publish' do
      it 'calls registered listeners with the event' do
        received_events = []
        listener = ->(event) { received_events << event }
        dispatcher.register(Conductor::Worker::Events::PollStarted, listener)

        event = Conductor::Worker::Events::PollStarted.new(
          task_type: 'my_task',
          worker_id: 'worker-1',
          poll_count: 5
        )
        dispatcher.publish(event)

        expect(received_events.size).to eq(1)
        expect(received_events.first.task_type).to eq('my_task')
      end

      it 'isolates listener exceptions' do
        good_events = []
        bad_listener = ->(_event) { raise 'Listener error!' }
        good_listener = ->(event) { good_events << event }

        dispatcher.register(Conductor::Worker::Events::PollStarted, bad_listener)
        dispatcher.register(Conductor::Worker::Events::PollStarted, good_listener)

        event = Conductor::Worker::Events::PollStarted.new(
          task_type: 'my_task',
          worker_id: 'worker-1',
          poll_count: 0
        )

        # Should not raise
        expect { dispatcher.publish(event) }.not_to raise_error

        # Good listener should still be called
        expect(good_events.size).to eq(1)
      end
    end

    describe '#clear' do
      it 'removes all listeners' do
        dispatcher.register(Conductor::Worker::Events::PollStarted, ->(e) { e })
        dispatcher.register(Conductor::Worker::Events::PollCompleted, ->(e) { e })
        dispatcher.clear

        expect(dispatcher.has_listeners?(Conductor::Worker::Events::PollStarted)).to be false
        expect(dispatcher.has_listeners?(Conductor::Worker::Events::PollCompleted)).to be false
      end
    end
  end

  describe Conductor::Worker::Events::PollStarted do
    it 'creates an event with correct attributes' do
      event = described_class.new(
        task_type: 'my_task',
        worker_id: 'worker-1',
        poll_count: 10
      )

      expect(event.task_type).to eq('my_task')
      expect(event.worker_id).to eq('worker-1')
      expect(event.poll_count).to eq(10)
      expect(event.timestamp).to be_a(Time)
    end

    it 'converts to hash' do
      event = described_class.new(
        task_type: 'my_task',
        worker_id: 'worker-1',
        poll_count: 10
      )

      hash = event.to_h
      expect(hash[:task_type]).to eq('my_task')
      expect(hash[:worker_id]).to eq('worker-1')
      expect(hash[:poll_count]).to eq(10)
    end
  end

  describe Conductor::Worker::Events::TaskExecutionCompleted do
    it 'creates an event with correct attributes' do
      event = described_class.new(
        task_type: 'my_task',
        task_id: 'task-123',
        worker_id: 'worker-1',
        workflow_instance_id: 'workflow-456',
        duration_ms: 150.5,
        output_size_bytes: 1024
      )

      expect(event.task_type).to eq('my_task')
      expect(event.task_id).to eq('task-123')
      expect(event.duration_ms).to eq(150.5)
      expect(event.output_size_bytes).to eq(1024)
    end
  end

  describe Conductor::Worker::Events::TaskUpdateFailure do
    it 'includes task_result for recovery' do
      task_result = Conductor::Http::Models::TaskResult.complete
      error = StandardError.new('Update failed')

      event = described_class.new(
        task_type: 'my_task',
        task_id: 'task-123',
        worker_id: 'worker-1',
        workflow_instance_id: 'workflow-456',
        cause: error,
        retry_count: 4,
        task_result: task_result
      )

      expect(event.task_result).to eq(task_result)
      expect(event.retry_count).to eq(4)
      expect(event.cause).to eq(error)
    end
  end

  describe Conductor::Worker::Events::ListenerRegistry do
    let(:dispatcher) { Conductor::Worker::Events::SyncEventDispatcher.new }

    it 'registers all implemented listener methods' do
      events_received = []

      listener = Class.new do
        define_method(:on_poll_started) { |event| events_received << [:poll_started, event] }
        define_method(:on_poll_completed) { |event| events_received << [:poll_completed, event] }
      end.new

      described_class.register_task_runner_listener(listener, dispatcher)

      # Publish events
      dispatcher.publish(Conductor::Worker::Events::PollStarted.new(
        task_type: 'test', worker_id: 'w1', poll_count: 0
      ))
      dispatcher.publish(Conductor::Worker::Events::PollCompleted.new(
        task_type: 'test', duration_ms: 10, tasks_received: 1
      ))

      expect(events_received.size).to eq(2)
      expect(events_received[0][0]).to eq(:poll_started)
      expect(events_received[1][0]).to eq(:poll_completed)
    end

    it 'skips methods not implemented by listener' do
      listener = Class.new do
        define_method(:on_poll_started) { |_event| 'started' }
        # Does not implement on_poll_completed
      end.new

      described_class.register_task_runner_listener(listener, dispatcher)

      expect(dispatcher.has_listeners?(Conductor::Worker::Events::PollStarted)).to be true
      expect(dispatcher.has_listeners?(Conductor::Worker::Events::PollCompleted)).to be false
    end
  end
end
