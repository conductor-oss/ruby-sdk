# frozen_string_literal: true

require 'spec_helper'

# Conditionally load the Ractor runner
ractor_runner_loaded = begin
  require_relative '../../../lib/conductor/worker/ractor_task_runner'
  # Reset the memoized availability immediately after loading
  # to ensure clean state for tests
  Conductor::Worker::RactorSupport.remove_instance_variable(:@available) if Conductor::Worker::RactorSupport.instance_variable_defined?(:@available)
  true
rescue LoadError
  false
end

# Ractor tests are conditional - only run on Ruby 3.1+
RSpec.describe 'RactorTaskRunner', if: RUBY_VERSION >= '3.1' && ractor_runner_loaded do
  describe Conductor::Worker::RactorTaskRunner do
    let(:configuration) do
      Conductor::Configuration.new(server_api_url: 'http://localhost:8080/api')
    end

    let(:worker) do
      Conductor::Worker::Worker.new('test_task', poll_interval: 100) do |task|
        { result: task.input_data['value'] * 2 }
      end
    end

    describe '#initialize' do
      it 'creates a runner with serialized configuration' do
        runner = described_class.new(worker, configuration: configuration, ractor_id: 0)

        expect(runner.worker).to eq(worker)
        expect(runner.ractor_id).to eq(0)
      end

      it 'accepts a custom ractor_id' do
        runner = described_class.new(worker, configuration: configuration, ractor_id: 5)

        expect(runner.ractor_id).to eq(5)
      end
    end

    describe '#shutdown' do
      it 'signals the runner to stop' do
        runner = described_class.new(worker, configuration: configuration)
        expect { runner.shutdown }.not_to raise_error
      end
    end

    describe 'event publishing helpers' do
      let(:runner) do
        described_class.new(worker, configuration: configuration, ractor_id: 0)
      end

      let(:task_result) do
        Conductor::Http::Models::TaskResult.new.tap do |r|
          r.task_id = 'task-123'
          r.workflow_instance_id = 'workflow-456'
        end
      end

      before do
        runner.instance_variable_set(:@worker_id, 'test-worker-ractor-0')
      end

      describe '#publish_task_update_completed' do
        it 'publishes a TaskUpdateCompleted event with duration_ms' do
          published = nil
          allow(runner).to receive(:publish_event) { |event| published = event }

          runner.send(:publish_task_update_completed, task_result, 42.5)

          expect(published).to be_a(Conductor::Worker::Events::TaskUpdateCompleted)
          expect(published.task_type).to eq('test_task')
          expect(published.task_id).to eq('task-123')
          expect(published.duration_ms).to eq(42.5)
        end
      end

      describe '#publish_task_update_failure' do
        it 'publishes a TaskUpdateFailure event with duration_ms' do
          published = nil
          allow(runner).to receive(:publish_event) { |event| published = event }

          error = StandardError.new('update failed')
          runner.send(:publish_task_update_failure, task_result, error, 99.0)

          expect(published).to be_a(Conductor::Worker::Events::TaskUpdateFailure)
          expect(published.task_type).to eq('test_task')
          expect(published.cause).to eq(error)
          expect(published.duration_ms).to eq(99.0)
          expect(published.retry_count).to eq(Conductor::Worker::RactorTaskRunner::RETRY_BACKOFFS.size)
        end
      end

      describe '#publish_uncaught_exception' do
        it 'publishes a ThreadUncaughtException event' do
          published = nil
          allow(runner).to receive(:publish_event) { |event| published = event }

          error = RuntimeError.new('crash')
          runner.send(:publish_uncaught_exception, error)

          expect(published).to be_a(Conductor::Worker::Events::ThreadUncaughtException)
          expect(published.cause).to eq(error)
          expect(published.task_type).to eq('test_task')
        end

        it 'does not raise when publish_event fails' do
          allow(runner).to receive(:publish_event).and_raise(StandardError.new('dispatch error'))

          expect { runner.send(:publish_uncaught_exception, RuntimeError.new('test')) }.not_to raise_error
        end
      end
    end

    describe 'poll_task when paused' do
      let(:paused_worker) do
        Conductor::Worker::Worker.new('test_task', poll_interval: 100, paused: true) do |task|
          { result: task.input_data['value'] }
        end
      end

      it 'publishes TaskPaused and returns nil' do
        runner = described_class.new(paused_worker, configuration: configuration, ractor_id: 0)
        runner.instance_variable_set(:@worker_id, 'test-worker-ractor-0')

        published = nil
        allow(runner).to receive(:publish_event) { |event| published = event }

        result = runner.send(:poll_task)

        expect(result).to be_nil
        expect(published).to be_a(Conductor::Worker::Events::TaskPaused)
        expect(published.task_type).to eq('test_task')
      end
    end
  end

  describe Conductor::Worker::RactorSupport do
    before do
      # Reset the memoized availability check before each test
      described_class.remove_instance_variable(:@available) if described_class.instance_variable_defined?(:@available)
    end

    describe '.available?' do
      it 'returns true on Ruby 3.1+' do
        expect(described_class.available?).to be true
      end
    end

    describe '.require_ractors!' do
      it 'does not raise on Ruby 3.1+' do
        expect { described_class.require_ractors! }.not_to raise_error
      end
    end
  end
end

# Test RactorSupport on older Ruby versions
RSpec.describe 'RactorSupport (Ruby < 3.1)', if: RUBY_VERSION < '3.1' && ractor_runner_loaded do
  describe Conductor::Worker::RactorSupport do
    before do
      # Reset the memoized availability check before each test
      described_class.remove_instance_variable(:@available) if described_class.instance_variable_defined?(:@available)
    end

    describe '.available?' do
      it 'returns false on older Ruby versions' do
        expect(described_class.available?).to be false
      end
    end

    describe '.require_ractors!' do
      it 'raises ConfigurationError on older Ruby versions' do
        expect { described_class.require_ractors! }.to raise_error(Conductor::ConfigurationError)
      end
    end
  end
end
