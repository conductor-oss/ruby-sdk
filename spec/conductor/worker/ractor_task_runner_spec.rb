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
