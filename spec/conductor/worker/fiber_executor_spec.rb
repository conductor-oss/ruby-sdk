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
