# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Conductor::Worker::TaskRunner, '#send_task_update' do
  let(:configuration) { Conductor::Configuration.new(server_api_url: 'http://localhost:8080/api') }
  let(:task_client) { instance_double(Conductor::Client::TaskClient) }
  let(:worker) { Conductor::Worker::Worker.new('t') { {} } }
  let(:runner) do
    allow(Conductor::Client::TaskClient).to receive(:new).and_return(task_client)
    described_class.new(worker, configuration: configuration, logger: Logger.new(nil))
  end
  let(:result) { Conductor::Http::Models::TaskResult.complete }

  it 'posts to update-v2 with extendLease false by default' do
    expect(task_client).to receive(:update_task_v2) do |task_result|
      expect(task_result.extend_lease).to be false
      nil
    end
    runner.send(:send_task_update, result)
  end

  it 'falls back to /tasks once when the server does not serve update-v2' do
    expect(task_client).to receive(:update_task_v2).once.and_raise(Conductor::ApiError.new('nope', status: 404))
    expect(task_client).to receive(:update_task).twice
    runner.send(:send_task_update, result)
    runner.send(:send_task_update, result)
  end

  it 're-raises other API errors' do
    allow(task_client).to receive(:update_task_v2).and_raise(Conductor::ApiError.new('boom', status: 500))
    expect { runner.send(:send_task_update, result) }.to raise_error(Conductor::ApiError)
  end

  it 'executes every task claimed by update-v2 on the same executor slot' do
    tasks = (1..3).map { |id| Conductor::Http::Models::Task.new(task_id: id.to_s, workflow_instance_id: 'wf', input_data: {}) }
    allow(worker).to receive(:execute).and_call_original
    expect(task_client).to receive(:update_task_v2).with(have_attributes(task_id: '1')).ordered.and_return(tasks[1])
    expect(task_client).to receive(:update_task_v2).with(have_attributes(task_id: '2')).ordered.and_return(tasks[2])
    expect(task_client).to receive(:update_task_v2).with(have_attributes(task_id: '3')).ordered.and_return(nil)
    runner.send(:execute_and_update, tasks.first)
    tasks.each { |task| expect(worker).to have_received(:execute).with(task).once }
    expect(Conductor::Worker::TaskContext.current).to be_nil
  end

  it 'does not claim more tasks after shutdown' do
    runner.shutdown
    expect(task_client).not_to receive(:update_task_v2)
    expect(task_client).to receive(:update_task).with(result)
    runner.send(:send_task_update, result)
  end
end

RSpec.describe Conductor::Worker::Worker, '#lease_extend_enabled' do
  it 'defaults to false and can be enabled' do
    expect(described_class.new('t') { {} }.lease_extend_enabled).to be false
    expect(described_class.new('t', lease_extend_enabled: true) { {} }.lease_extend_enabled).to be true
  end
end
