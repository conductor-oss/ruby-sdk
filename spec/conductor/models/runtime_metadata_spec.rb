# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Conductor::Http::Models::Task, '#runtime_metadata' do
  it 'defaults to an empty hash' do
    expect(described_class.new.runtime_metadata).to eq({})
  end

  it 'deserializes the wire-only secret map from a poll response' do
    task = described_class.from_hash(
      'taskType' => 'create_issue',
      'taskId' => 'TASK_1',
      'inputData' => { 'title' => 'bug' },
      'runtimeMetadata' => { 'GH_TOKEN' => 'ghp_secret' }
    )
    expect(task.runtime_metadata).to eq('GH_TOKEN' => 'ghp_secret')
  end
end

RSpec.describe Conductor::Http::Models::TaskDef, '#runtime_metadata' do
  it 'defaults to an empty list and enforce_schema false' do
    task_def = described_class.new(name: 't')
    expect(task_def.runtime_metadata).to eq([])
    expect(task_def.enforce_schema).to be false
  end

  it 'serializes secret names as runtimeMetadata' do
    task_def = described_class.new(name: 'create_issue', runtime_metadata: ['GH_TOKEN'])
    hash = task_def.to_h
    expect(hash['runtimeMetadata']).to eq(['GH_TOKEN'])
    expect(hash['enforceSchema']).to be false
  end

  it 'keeps agent worker defaults when used as a template (timeout 0 is not overridden)' do
    template = described_class.new(name: 'x', timeout_seconds: 0, response_timeout_seconds: 10,
                                   retry_count: 2, retry_delay_seconds: 2,
                                   retry_logic: 'LINEAR_BACKOFF', timeout_policy: 'RETRY',
                                   runtime_metadata: ['GH_TOKEN'])
    worker = Conductor::Worker::Worker.new('get_weather', register_task_def: true,
                                                          task_def_template: template) { {} }
    registrar = Conductor::Worker::TaskDefinitionRegistrar.new(Conductor::Configuration.new, logger: Logger.new(nil))
    task_def = registrar.send(:build_task_definition, worker)

    expect(task_def.name).to eq('get_weather')
    expect(task_def.timeout_seconds).to eq(0)
    expect(task_def.response_timeout_seconds).to eq(10)
    expect(task_def.retry_count).to eq(2)
    expect(task_def.retry_logic).to eq('LINEAR_BACKOFF')
    expect(task_def.timeout_policy).to eq('RETRY')
    expect(task_def.runtime_metadata).to eq(['GH_TOKEN'])
  end
end
