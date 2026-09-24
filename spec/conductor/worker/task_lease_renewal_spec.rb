# frozen_string_literal: true

require 'spec_helper'
require 'timeout'

RSpec.describe Conductor::Worker::TaskRunner, '#execute_task' do
  let(:client) { instance_double(Conductor::Client::TaskClient) }
  let(:heartbeats) { Queue.new }
  let(:heartbeat_threads) { [] }
  let(:worker) do
    Conductor::Worker::Worker.new('long_tool', lease_extend_enabled: true, worker_id: 'worker-1') do |task|
      result = Timeout.timeout(2) { heartbeats.pop }
      expect(result.task_id).to eq(task.task_id)
      { 'done' => true }
    end
  end
  let(:runner) do
    described_class.new(worker, configuration: Conductor::Configuration.new, logger: Logger.new(nil))
  end
  let(:task) do
    Conductor::Http::Models::Task.new(task_id: 'task-1', workflow_instance_id: 'workflow-1', response_timeout_seconds: 0.02)
  end

  before do
    allow(Conductor::Client::TaskClient).to receive(:new).and_return(client)
    allow(client).to receive(:update_task) do |result|
      heartbeat_threads << Thread.current
      heartbeats << result
    end
  end

  it 'renews each claimed task and stops its heartbeat before submitting the final result' do
    next_task = Conductor::Http::Models::Task.new(task_id: 'task-2', workflow_instance_id: 'workflow-1', response_timeout_seconds: 0.02)
    expect(client).to receive(:update_task_v2).with(have_attributes(task_id: 'task-1', status: 'COMPLETED', extend_lease: false)).ordered do
      expect(heartbeat_threads.last).not_to be_alive
      next_task
    end
    expect(client).to receive(:update_task_v2).with(have_attributes(task_id: 'task-2', status: 'COMPLETED', extend_lease: false)).ordered do
      expect(heartbeat_threads.last).not_to be_alive
      nil
    end

    runner.send(:execute_and_update, task)
    expect(client).to have_received(:update_task).with(have_attributes(worker_id: 'worker-1', status: 'IN_PROGRESS', extend_lease: true)).at_least(:twice)
  end

  it 'honors an environment override that disables renewal' do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('CONDUCTOR_WORKER_LONG_TOOL_LEASE_EXTEND_ENABLED', nil).and_return('false')
    allow(worker).to receive(:execute).and_return(Conductor::Http::Models::TaskResult.complete)
    expect(client).not_to receive(:update_task)
    runner.send(:execute_task, task)
  end

  it 'keeps renewing an executing task during graceful shutdown' do
    active_runner = runner
    allow(worker).to receive(:execute) do
      active_runner.shutdown
      result = Timeout.timeout(2) { heartbeats.pop }
      expect(result.extend_lease).to be true
      Conductor::Http::Models::TaskResult.complete
    end
    expect(runner.send(:execute_task, task).status).to eq('COMPLETED')
  end
end
