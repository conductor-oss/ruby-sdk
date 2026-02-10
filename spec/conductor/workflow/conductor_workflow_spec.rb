# frozen_string_literal: true

RSpec.describe Conductor::Workflow::ConductorWorkflow do
  let(:workflow_client) { instance_double(Conductor::Client::WorkflowClient) }

  describe '#initialize' do
    it 'creates a workflow with name' do
      workflow = described_class.new(workflow_client, 'my_workflow')

      expect(workflow.name).to eq('my_workflow')
      expect(workflow.version).to be_nil
      expect(workflow.description).to be_nil
      expect(workflow.tasks).to eq([])
    end

    it 'accepts optional parameters' do
      workflow = described_class.new(
        workflow_client,
        'my_workflow',
        version: 1,
        description: 'Test workflow'
      )

      expect(workflow.version).to eq(1)
      expect(workflow.description).to eq('Test workflow')
    end
  end

  describe 'fluent configuration methods' do
    let(:workflow) { described_class.new(workflow_client, 'my_workflow') }

    it 'supports description' do
      result = workflow.description('My description')
      expect(result).to eq(workflow)
      expect(workflow.description).to eq('My description')
    end

    it 'supports timeout_seconds' do
      result = workflow.timeout_seconds(3600)
      expect(result).to eq(workflow)
    end

    it 'supports timeout_policy' do
      result = workflow.timeout_policy(Conductor::Workflow::TimeoutPolicy::TIME_OUT_WORKFLOW)
      expect(result).to eq(workflow)
    end

    it 'supports owner_email' do
      result = workflow.owner_email('test@example.com')
      expect(result).to eq(workflow)
    end

    it 'supports failure_workflow' do
      result = workflow.failure_workflow('compensation_workflow')
      expect(result).to eq(workflow)
    end

    it 'supports restartable' do
      result = workflow.restartable(false)
      expect(result).to eq(workflow)
    end

    it 'supports output_parameters' do
      result = workflow.output_parameters({ 'result' => '${task_ref.output}' })
      expect(result).to eq(workflow)
    end

    it 'supports output_parameter' do
      result = workflow.output_parameter('key', 'value')
      expect(result).to eq(workflow)
    end

    it 'supports input_parameters' do
      result = workflow.input_parameters(%w[param1 param2])
      expect(result).to eq(workflow)
    end

    it 'supports variables' do
      result = workflow.variables({ 'counter' => 0 })
      expect(result).to eq(workflow)
    end
  end

  describe '#>>' do
    let(:workflow) { described_class.new(workflow_client, 'my_workflow') }
    let(:task1) { Conductor::Workflow::SimpleTask.new('task1_def', 'task1_ref') }
    let(:task2) { Conductor::Workflow::SimpleTask.new('task2_def', 'task2_ref') }

    it 'adds a single task' do
      workflow >> task1

      expect(workflow.tasks.length).to eq(1)
      expect(workflow.tasks.first.task_reference_name).to eq('task1_ref')
    end

    it 'chains multiple tasks' do
      workflow >> task1 >> task2

      expect(workflow.tasks.length).to eq(2)
      expect(workflow.tasks[0].task_reference_name).to eq('task1_ref')
      expect(workflow.tasks[1].task_reference_name).to eq('task2_ref')
    end

    it 'creates fork-join for array of arrays' do
      branch1_task = Conductor::Workflow::SimpleTask.new('branch1', 'branch1_ref')
      branch2_task = Conductor::Workflow::SimpleTask.new('branch2', 'branch2_ref')

      workflow >> [[branch1_task], [branch2_task]]

      expect(workflow.tasks.length).to eq(1)
      expect(workflow.tasks.first).to be_a(Conductor::Workflow::ForkTask)
    end

    it 'returns self for chaining' do
      result = workflow >> task1
      expect(result).to eq(workflow)
    end
  end

  describe '#add' do
    let(:workflow) { described_class.new(workflow_client, 'my_workflow') }
    let(:task) { Conductor::Workflow::SimpleTask.new('task_def', 'task_ref') }

    it 'adds a single task' do
      workflow.add(task)
      expect(workflow.tasks.length).to eq(1)
    end

    it 'adds multiple tasks from array' do
      task2 = Conductor::Workflow::SimpleTask.new('task2_def', 'task2_ref')
      workflow.add([task, task2])
      expect(workflow.tasks.length).to eq(2)
    end
  end

  describe '#input' do
    let(:workflow) { described_class.new(workflow_client, 'my_workflow') }

    it 'returns input expression without path' do
      expect(workflow.input).to eq('${workflow.input}')
    end

    it 'returns input expression with path' do
      expect(workflow.input('userId')).to eq('${workflow.input.userId}')
    end
  end

  describe '#output' do
    let(:workflow) { described_class.new(workflow_client, 'my_workflow') }

    it 'returns output expression without path' do
      expect(workflow.output).to eq('${workflow.output}')
    end

    it 'returns output expression with path' do
      expect(workflow.output('result')).to eq('${workflow.output.result}')
    end
  end

  describe '#to_workflow_def' do
    let(:workflow) do
      wf = described_class.new(workflow_client, 'test_workflow', version: 1)
      wf.description('Test')
      wf.timeout_seconds(3600)
      wf.owner_email('test@example.com')
      wf
    end

    it 'converts to WorkflowDef model' do
      task = Conductor::Workflow::SimpleTask.new('task_def', 'task_ref')
      workflow >> task

      wf_def = workflow.to_workflow_def

      expect(wf_def).to be_a(Conductor::Http::Models::WorkflowDef)
      expect(wf_def.name).to eq('test_workflow')
      expect(wf_def.version).to eq(1)
      expect(wf_def.description).to eq('Test')
      expect(wf_def.timeout_seconds).to eq(3600)
      expect(wf_def.owner_email).to eq('test@example.com')
      expect(wf_def.tasks.length).to eq(1)
    end

    it 'includes schema version 2' do
      wf_def = workflow.to_workflow_def
      expect(wf_def.schema_version).to eq(2)
    end
  end
end
