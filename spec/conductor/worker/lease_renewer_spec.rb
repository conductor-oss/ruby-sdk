# frozen_string_literal: true

require 'spec_helper'
require 'timeout'
require 'conductor/worker/lease_renewer'

RSpec.describe Conductor::Worker::LeaseRenewer do
  let(:client) { instance_double(Conductor::Client::TaskClient) }
  let(:logger) { instance_double(Logger, warn: nil) }
  let(:renewer) { described_class.new(task_client: client, logger: logger) }
  let(:task) do
    Conductor::Http::Models::Task.new(task_id: 'task-1', workflow_instance_id: 'workflow-1', response_timeout_seconds: 0.02)
  end

  it 'renews repeatedly while the body runs, returns its value and stops afterward' do
    heartbeats = Queue.new
    expect(client).not_to receive(:update_task_v2)
    allow(client).to receive(:update_task) do |result|
      heartbeats << [result, Thread.current]
    end

    heartbeat_thread = nil
    value = renewer.during(task, worker_id: 'worker-1') do
      2.times do
        result, heartbeat_thread = Timeout.timeout(2) { heartbeats.pop }
        expect(result).to have_attributes(
          task_id: 'task-1', workflow_instance_id: 'workflow-1', worker_id: 'worker-1',
          status: 'IN_PROGRESS', extend_lease: true, output_data: {}
        )
      end
      :finished
    end

    expect(value).to eq(:finished)
    expect(heartbeat_thread).not_to be_alive
  end

  [nil, 0, -1].each do |timeout|
    it "does not renew a task with response timeout #{timeout.inspect}" do
      task.response_timeout_seconds = timeout
      expect(client).not_to receive(:update_task)
      expect(renewer.during(task, worker_id: 'worker-1') { :finished }).to eq(:finished)
    end
  end

  it 'stops renewal when the body raises and preserves the exception' do
    heartbeats = Queue.new
    allow(client).to receive(:update_task) { heartbeats << Thread.current }
    heartbeat_thread = nil

    expect do
      renewer.during(task, worker_id: 'worker-1') do
        heartbeat_thread = Timeout.timeout(2) { heartbeats.pop }
        raise 'tool failed'
      end
    end.to raise_error(RuntimeError, 'tool failed')

    expect(heartbeat_thread).not_to be_alive
  end

  it 'logs a failed renewal and continues renewing without failing the body' do
    heartbeats = Queue.new
    calls = 0
    allow(client).to receive(:update_task) do
      calls += 1
      raise Conductor::ApiError.new('temporarily unavailable', status: 503) if calls == 1

      heartbeats << true
    end

    expect(renewer.during(task, worker_id: 'worker-1') { Timeout.timeout(2) { heartbeats.pop } }).to be true
    expect(logger).to have_received(:warn).with(/Lease renewal failed for task task-1/)
  end

  it 'drains an in-flight renewal before returning to the caller' do
    started = Queue.new
    release = Queue.new
    body_finished = Queue.new
    allow(client).to receive(:update_task) do
      started << true
      release.pop
    end
    execution = Thread.new do
      renewer.during(task, worker_id: 'worker-1') do
        started.pop
        body_finished << true
      end
      :finished
    end

    Timeout.timeout(2) { body_finished.pop }
    expect(execution.join(0.02)).to be_nil
    release << true
    expect(Timeout.timeout(2) { execution.value }).to eq(:finished)
  ensure
    release << true
    execution&.join(2)
    execution&.kill
  end
end
