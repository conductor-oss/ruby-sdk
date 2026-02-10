# frozen_string_literal: true

require_relative 'integration_helper'

RSpec.describe 'Workflow Execution Integration', :integration do
  let(:metadata_client) { IntegrationHelper.metadata_client }
  let(:workflow_client) { IntegrationHelper.workflow_client }
  let(:task_client) { IntegrationHelper.task_client }

  let(:task_name) { IntegrationHelper.test_name('wf_exec_task') }
  let(:workflow_name) { IntegrationHelper.test_name('wf_exec_workflow') }

  before(:all) do
    # Skip setup if integration tests disabled
    next unless ENV['CONDUCTOR_INTEGRATION'] == 'true'
    next unless IntegrationHelper.server_available?

    @task_name = IntegrationHelper.test_name('wf_exec_task')
    @workflow_name = IntegrationHelper.test_name('wf_exec_workflow')

    # Register task definition
    task_def = Conductor::Http::Models::TaskDef.new
    task_def.name = @task_name
    task_def.timeout_seconds = 60
    task_def.response_timeout_seconds = 30
    task_def.retry_count = 0
    IntegrationHelper.metadata_client.register_task_def(task_def)

    # Register a simple workflow
    task = Conductor::Http::Models::WorkflowTask.new
    task.name = @task_name
    task.task_reference_name = "#{@task_name}_ref"
    task.type = 'SIMPLE'
    task.input_parameters = { 'value' => '${workflow.input.value}' }

    workflow_def = Conductor::Http::Models::WorkflowDef.new
    workflow_def.name = @workflow_name
    workflow_def.version = 1
    workflow_def.description = 'Workflow execution integration test'
    workflow_def.tasks = [task]
    workflow_def.schema_version = 2
    workflow_def.timeout_seconds = 300
    workflow_def.timeout_policy = 'TIME_OUT_WF'
    workflow_def.owner_email = 'test@example.com'
    IntegrationHelper.metadata_client.register_workflow_def(workflow_def)
  end

  after(:all) do
    next unless ENV['CONDUCTOR_INTEGRATION'] == 'true'
    next unless IntegrationHelper.server_available?

    IntegrationHelper.cleanup_workflow_def(@workflow_name, version: 1)
    IntegrationHelper.cleanup_task_def(@task_name)
  end

  # ==========================================
  # Start Workflow
  # ==========================================
  describe 'Starting a workflow' do
    it 'starts a workflow and returns a workflow ID' do
      workflow_id = workflow_client.start(@workflow_name, input: { 'value' => 'hello' })

      expect(workflow_id).to be_a(String)
      expect(workflow_id).not_to be_empty

      # Cleanup
      IntegrationHelper.cleanup_workflow(workflow_id)
    end

    it 'starts a workflow with StartWorkflowRequest' do
      request = Conductor::Http::Models::StartWorkflowRequest.new(
        name: @workflow_name,
        version: 1,
        input: { 'value' => 'test_request' }
      )

      workflow_id = workflow_client.start_workflow(request)

      expect(workflow_id).to be_a(String)
      expect(workflow_id).not_to be_empty

      IntegrationHelper.cleanup_workflow(workflow_id)
    end

    it 'starts a workflow with a correlation ID' do
      correlation_id = "corr_#{rand(100_000)}"
      workflow_id = workflow_client.start(
        @workflow_name,
        input: { 'value' => 'correlated' },
        correlation_id: correlation_id
      )

      expect(workflow_id).to be_a(String)

      # Verify correlation ID is set
      wf = workflow_client.get_workflow(workflow_id)
      expect(wf.correlation_id).to eq(correlation_id)

      IntegrationHelper.cleanup_workflow(workflow_id)
    end
  end

  # ==========================================
  # Get Workflow Status
  # ==========================================
  describe 'Getting workflow status' do
    it 'gets workflow execution status with tasks' do
      workflow_id = workflow_client.start(@workflow_name, input: { 'value' => 'status_test' })

      wf = workflow_client.get_workflow(workflow_id, include_tasks: true)

      expect(wf).to be_a(Conductor::Http::Models::Workflow)
      expect(wf.workflow_id).to eq(workflow_id)
      expect(wf.workflow_name).to eq(@workflow_name)
      expect(wf.status).to eq(Conductor::Http::Models::WorkflowStatusConstants::RUNNING)
      expect(wf.tasks).to be_an(Array)
      expect(wf.input).to eq({ 'value' => 'status_test' })

      IntegrationHelper.cleanup_workflow(workflow_id)
    end

    it 'gets workflow status without tasks' do
      workflow_id = workflow_client.start(@workflow_name, input: { 'value' => 'no_tasks' })

      wf = workflow_client.get_workflow(workflow_id, include_tasks: false)

      expect(wf.workflow_id).to eq(workflow_id)
      # Tasks may be empty or nil depending on server behavior
      expect(wf.tasks.nil? || wf.tasks.empty?).to be true

      IntegrationHelper.cleanup_workflow(workflow_id)
    end
  end

  # ==========================================
  # Pause / Resume Workflow
  # ==========================================
  describe 'Pause and resume workflow' do
    it 'pauses and resumes a running workflow' do
      workflow_id = workflow_client.start(@workflow_name, input: { 'value' => 'pause_test' })

      # Pause
      expect { workflow_client.pause_workflow(workflow_id) }.not_to raise_error

      # Verify paused
      wf = workflow_client.get_workflow(workflow_id)
      expect(wf.status).to eq(Conductor::Http::Models::WorkflowStatusConstants::PAUSED)

      # Resume
      expect { workflow_client.resume_workflow(workflow_id) }.not_to raise_error

      # Verify running again
      wf = workflow_client.get_workflow(workflow_id)
      expect(wf.status).to eq(Conductor::Http::Models::WorkflowStatusConstants::RUNNING)

      IntegrationHelper.cleanup_workflow(workflow_id)
    end
  end

  # ==========================================
  # Terminate Workflow
  # ==========================================
  describe 'Terminating a workflow' do
    it 'terminates a running workflow' do
      workflow_id = workflow_client.start(@workflow_name, input: { 'value' => 'terminate_test' })

      workflow_client.terminate_workflow(workflow_id, reason: 'Integration test termination')

      wf = workflow_client.get_workflow(workflow_id)
      expect(wf.status).to eq(Conductor::Http::Models::WorkflowStatusConstants::TERMINATED)
    end
  end

  # ==========================================
  # Task Polling and Update
  # ==========================================
  describe 'Task polling and update' do
    it 'polls for a task and updates it successfully' do
      workflow_id = workflow_client.start(@workflow_name, input: { 'value' => 'poll_test' })

      # Poll for the task
      tasks = task_client.batch_poll_tasks(@task_name, count: 1, timeout: 5000)
      expect(tasks).to be_an(Array)
      expect(tasks.length).to eq(1)

      task = tasks.first
      expect(task).to be_a(Conductor::Http::Models::Task)
      expect(task.task_type).to eq(@task_name)
      expect(task.input_data).to include('value' => 'poll_test')

      # Update with success
      task_result = Conductor::Http::Models::TaskResult.complete
      task_result.task_id = task.task_id
      task_result.workflow_instance_id = task.workflow_instance_id
      task_result.output_data = { 'processed' => true, 'original_value' => 'poll_test' }

      expect { task_client.update_task(task_result) }.not_to raise_error

      # Wait for workflow to complete
      wf = IntegrationHelper.wait_for_workflow(workflow_id, timeout: 10)
      expect(wf.status).to eq(Conductor::Http::Models::WorkflowStatusConstants::COMPLETED)
    end

    it 'polls for a task and fails it' do
      workflow_id = workflow_client.start(@workflow_name, input: { 'value' => 'fail_test' })

      # Poll for the task
      tasks = task_client.batch_poll_tasks(@task_name, count: 1, timeout: 5000)
      expect(tasks.length).to eq(1)

      task = tasks.first

      # Fail the task
      task_result = Conductor::Http::Models::TaskResult.failed_with_terminal_error('Intentional failure')
      task_result.task_id = task.task_id
      task_result.workflow_instance_id = task.workflow_instance_id

      expect { task_client.update_task(task_result) }.not_to raise_error

      # Wait for workflow to fail
      wf = IntegrationHelper.wait_for_workflow(workflow_id, timeout: 10)
      expect(wf.status).to eq(Conductor::Http::Models::WorkflowStatusConstants::FAILED)
    end
  end

  # ==========================================
  # Restart / Retry Workflow
  # ==========================================
  describe 'Restart and retry workflow' do
    it 'restarts a terminated workflow' do
      workflow_id = workflow_client.start(@workflow_name, input: { 'value' => 'restart_test' })

      # Terminate first
      workflow_client.terminate_workflow(workflow_id, reason: 'Will restart')

      wf = workflow_client.get_workflow(workflow_id)
      expect(wf.status).to eq(Conductor::Http::Models::WorkflowStatusConstants::TERMINATED)

      # Restart
      expect { workflow_client.restart_workflow(workflow_id) }.not_to raise_error

      # Verify it's running again
      wf = workflow_client.get_workflow(workflow_id)
      expect(wf.status).to eq(Conductor::Http::Models::WorkflowStatusConstants::RUNNING)

      IntegrationHelper.cleanup_workflow(workflow_id)
    end
  end

  # ==========================================
  # Task Logs
  # ==========================================
  describe 'Task logs' do
    it 'adds and retrieves task execution logs' do
      workflow_id = workflow_client.start(@workflow_name, input: { 'value' => 'log_test' })

      # Poll for the task
      tasks = task_client.batch_poll_tasks(@task_name, count: 1, timeout: 5000)
      task = tasks.first

      # Add logs
      task_client.add_task_log(task.task_id, 'Test log message 1')
      task_client.add_task_log(task.task_id, 'Test log message 2')

      # Retrieve logs
      logs = task_client.get_task_logs(task.task_id)
      expect(logs).to be_an(Array)
      expect(logs.length).to eq(2)

      # Complete the task
      task_result = Conductor::Http::Models::TaskResult.complete
      task_result.task_id = task.task_id
      task_result.workflow_instance_id = task.workflow_instance_id
      task_client.update_task(task_result)

      IntegrationHelper.wait_for_workflow(workflow_id, timeout: 10)
    end
  end

  # ==========================================
  # Queue Operations
  # ==========================================
  describe 'Queue operations' do
    it 'gets all queue details' do
      # Start a workflow so there's something in the queue
      workflow_id = workflow_client.start(@workflow_name, input: { 'value' => 'queue_test' })

      # Small delay to let task get queued
      sleep(0.5)

      sizes = task_client.get_all_queue_details
      expect(sizes).to be_a(Hash)

      IntegrationHelper.cleanup_workflow(workflow_id)
    end
  end
end
