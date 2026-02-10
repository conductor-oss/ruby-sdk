# frozen_string_literal: true

RSpec.describe Conductor::Workflow::SimpleTask do
  describe '#initialize' do
    it 'creates a simple task with task def name and reference name' do
      task = described_class.new('my_worker_task', 'task_ref_1')

      expect(task.name).to eq('my_worker_task')
      expect(task.task_reference_name).to eq('task_ref_1')
      expect(task.task_type).to eq(Conductor::Workflow::TaskType::SIMPLE)
    end
  end

  describe '#to_workflow_task' do
    it 'converts to WorkflowTask with correct type' do
      task = described_class.new('greet_user', 'greet_ref')
      task.input('name', '${workflow.input.userName}')

      wf_task = task.to_workflow_task

      expect(wf_task.name).to eq('greet_user')
      expect(wf_task.task_reference_name).to eq('greet_ref')
      expect(wf_task.type).to eq('SIMPLE')
      expect(wf_task.input_parameters['name']).to eq('${workflow.input.userName}')
    end
  end
end

RSpec.describe 'Conductor::Workflow.simple_task' do
  it 'creates a SimpleTask with inputs' do
    task = Conductor::Workflow.simple_task('my_task', 'task_ref', {
                                             'userId' => '${workflow.input.userId}',
                                             'action' => 'process'
                                           })

    expect(task).to be_a(Conductor::Workflow::SimpleTask)
    expect(task.input_parameters['userId']).to eq('${workflow.input.userId}')
    expect(task.input_parameters['action']).to eq('process')
  end
end
