# frozen_string_literal: true

RSpec.describe Conductor::Workflow::TaskInterface do
  describe '#initialize' do
    it 'creates a task with required parameters' do
      task = described_class.new(
        task_reference_name: 'my_task',
        task_type: Conductor::Workflow::TaskType::SIMPLE
      )

      expect(task.task_reference_name).to eq('my_task')
      expect(task.task_type).to eq('SIMPLE')
      expect(task.name).to eq('my_task')
      expect(task.input_parameters).to eq({})
    end

    it 'accepts optional parameters' do
      task = described_class.new(
        task_reference_name: 'my_task',
        task_type: Conductor::Workflow::TaskType::SIMPLE,
        task_name: 'task_definition_name',
        description: 'A test task',
        optional: true
      )

      expect(task.name).to eq('task_definition_name')
      expect(task.description).to eq('A test task')
      expect(task.optional).to be true
    end
  end

  describe '#input_parameter' do
    it 'adds input parameters with fluent interface' do
      task = described_class.new(
        task_reference_name: 'my_task',
        task_type: Conductor::Workflow::TaskType::SIMPLE
      )

      result = task.input_parameter('key1', 'value1')
                   .input_parameter('key2', '${workflow.input.data}')

      expect(result).to eq(task)
      expect(task.input_parameters).to eq({
                                            'key1' => 'value1',
                                            'key2' => '${workflow.input.data}'
                                          })
    end
  end

  describe '#input' do
    it 'is an alias for input_parameter' do
      task = described_class.new(
        task_reference_name: 'my_task',
        task_type: Conductor::Workflow::TaskType::SIMPLE
      )

      task.input('name', 'John')
      expect(task.input_parameters['name']).to eq('John')
    end
  end

  describe '#output' do
    let(:task) do
      described_class.new(
        task_reference_name: 'my_task',
        task_type: Conductor::Workflow::TaskType::SIMPLE
      )
    end

    it 'returns output expression without path' do
      expect(task.output).to eq('${my_task.output}')
    end

    it 'returns output expression with path' do
      expect(task.output('result')).to eq('${my_task.output.result}')
    end

    it 'handles path starting with dot' do
      expect(task.output('.data.items')).to eq('${my_task.output.data.items}')
    end
  end

  describe '#cache' do
    it 'configures caching with fluent interface' do
      task = described_class.new(
        task_reference_name: 'my_task',
        task_type: Conductor::Workflow::TaskType::SIMPLE
      )

      result = task.cache('cache_key_123', 3600)

      expect(result).to eq(task)
      expect(task.cache_key).to eq('cache_key_123')
      expect(task.cache_ttl_second).to eq(3600)
    end
  end

  describe '#to_workflow_task' do
    it 'converts to WorkflowTask model' do
      task = described_class.new(
        task_reference_name: 'my_task',
        task_type: Conductor::Workflow::TaskType::SIMPLE,
        task_name: 'my_task_def',
        description: 'Test task'
      )
      task.input('data', '${workflow.input.data}')

      wf_task = task.to_workflow_task

      expect(wf_task).to be_a(Conductor::Http::Models::WorkflowTask)
      expect(wf_task.name).to eq('my_task_def')
      expect(wf_task.task_reference_name).to eq('my_task')
      expect(wf_task.type).to eq('SIMPLE')
      expect(wf_task.description).to eq('Test task')
      expect(wf_task.input_parameters).to eq({ 'data' => '${workflow.input.data}' })
    end

    it 'includes cache config when configured' do
      task = described_class.new(
        task_reference_name: 'my_task',
        task_type: Conductor::Workflow::TaskType::SIMPLE
      )
      task.cache('my_key', 300)

      wf_task = task.to_workflow_task

      expect(wf_task.cache_config).to be_a(Conductor::Http::Models::CacheConfig)
      expect(wf_task.cache_config.key).to eq('my_key')
      expect(wf_task.cache_config.ttl_in_second).to eq(300)
    end
  end
end
