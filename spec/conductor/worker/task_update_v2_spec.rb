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
end

RSpec.describe Conductor::Worker::Worker, '#lease_extend_enabled' do
  it 'defaults to false and can be enabled' do
    expect(described_class.new('t') { {} }.lease_extend_enabled).to be false
    expect(described_class.new('t', lease_extend_enabled: true) { {} }.lease_extend_enabled).to be true
  end
end
