# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Conductor::Worker::Worker do
  let(:task) do
    Conductor::Http::Models::Task.new.tap do |t|
      t.task_id = 'task-123'
      t.workflow_instance_id = 'workflow-456'
      t.input_data = { 'name' => 'Alice', 'age' => 30 }
    end
  end

  describe '#initialize' do
    it 'creates a worker with a block' do
      worker = described_class.new('my_task') { |t| { result: t.input_data['name'] } }
      expect(worker.task_definition_name).to eq('my_task')
      expect(worker.task_type).to eq('my_task')
    end

    it 'creates a worker with a proc' do
      execute_fn = ->(t) { { result: t.input_data['name'] } }
      worker = described_class.new('my_task', execute_fn)
      expect(worker.task_definition_name).to eq('my_task')
    end

    it 'applies default configuration values' do
      worker = described_class.new('my_task') { {} }
      expect(worker.poll_interval).to eq(100)
      expect(worker.thread_count).to eq(1)
      expect(worker.register_task_def).to eq(false)
    end

    it 'accepts custom configuration options' do
      worker = described_class.new('my_task', poll_interval: 200, thread_count: 5) { {} }
      expect(worker.poll_interval).to eq(200)
      expect(worker.thread_count).to eq(5)
    end

    it 'raises an error without execute function or block' do
      expect { described_class.new('my_task') }.to raise_error(ArgumentError, /execute_function or block required/)
    end
  end

  describe '#execute' do
    context 'when returning a Hash' do
      it 'wraps the hash in a COMPLETED TaskResult' do
        worker = described_class.new('my_task') { |t| { greeting: "Hello #{t.input_data['name']}" } }
        result = worker.execute(task)

        expect(result).to be_a(Conductor::Http::Models::TaskResult)
        expect(result.status).to eq(Conductor::Http::Models::TaskResultStatus::COMPLETED)
        expect(result.output_data).to eq(greeting: 'Hello Alice')
        expect(result.task_id).to eq('task-123')
      end
    end

    context 'when returning a TaskResult' do
      it 'uses the TaskResult directly' do
        worker = described_class.new('my_task') do |_t|
          result = Conductor::Http::Models::TaskResult.complete
          result.output_data = { custom: 'output' }
          result
        end
        result = worker.execute(task)

        expect(result.status).to eq(Conductor::Http::Models::TaskResultStatus::COMPLETED)
        expect(result.output_data).to eq(custom: 'output')
      end
    end

    context 'when returning true' do
      it 'creates a COMPLETED TaskResult' do
        worker = described_class.new('my_task') { |_t| true }
        result = worker.execute(task)

        expect(result.status).to eq(Conductor::Http::Models::TaskResultStatus::COMPLETED)
      end
    end

    context 'when returning false' do
      it 'creates a FAILED TaskResult' do
        worker = described_class.new('my_task') { |_t| false }
        result = worker.execute(task)

        expect(result.status).to eq(Conductor::Http::Models::TaskResultStatus::FAILED)
      end
    end

    context 'when returning nil' do
      it 'creates a COMPLETED TaskResult' do
        worker = described_class.new('my_task') { |_t| nil }
        result = worker.execute(task)

        expect(result.status).to eq(Conductor::Http::Models::TaskResultStatus::COMPLETED)
      end
    end

    context 'when returning TaskInProgress' do
      it 'creates an IN_PROGRESS TaskResult' do
        worker = described_class.new('my_task') do |_t|
          Conductor::Worker::TaskInProgress.new(callback_after_seconds: 30, output: { status: 'processing' })
        end
        result = worker.execute(task)

        expect(result.status).to eq(Conductor::Http::Models::TaskResultStatus::IN_PROGRESS)
        expect(result.callback_after_seconds).to eq(30)
        expect(result.output_data).to eq(status: 'processing')
      end
    end
  end

  describe '#polling_interval_seconds' do
    it 'converts poll_interval from ms to seconds' do
      worker = described_class.new('my_task', poll_interval: 500) { {} }
      expect(worker.polling_interval_seconds).to eq(0.5)
    end
  end
end

RSpec.describe Conductor::Worker::WorkerMixin do
  let(:worker_class) do
    Class.new do
      include Conductor::Worker::WorkerMixin

      worker_task 'test_worker', poll_interval: 150, thread_count: 3

      def execute(task)
        { processed: true, name: task.input_data['name'] }
      end
    end
  end

  describe '.worker_task' do
    it 'sets the task definition name' do
      expect(worker_class.task_definition_name).to eq('test_worker')
      expect(worker_class.task_type).to eq('test_worker')
    end

    it 'sets configuration options' do
      expect(worker_class.poll_interval).to eq(150)
      expect(worker_class.thread_count).to eq(3)
    end
  end

  describe '#execute' do
    it 'can be called on an instance' do
      worker = worker_class.new
      task = Conductor::Http::Models::Task.new
      task.input_data = { 'name' => 'Bob' }

      result = worker.execute(task)
      expect(result).to eq(processed: true, name: 'Bob')
    end
  end

  describe '#polling_interval_seconds' do
    it 'converts poll_interval from ms to seconds' do
      worker = worker_class.new
      expect(worker.polling_interval_seconds).to eq(0.15)
    end
  end
end
