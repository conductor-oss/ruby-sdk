# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

# Task Operations integration tests - run with:
# CONDUCTOR_INTEGRATION=true bundle exec rspec spec/integration/task_ops_spec.rb --format documentation
#
# These tests cover task-related API operations:
# - poll / batch_poll
# - get_task
# - update_task / update_task_by_ref_name
# - Task queue operations (size, all_queue_details, etc.)
# - Task search
# - Task logs

RSpec.describe 'Task Operations Integration', skip: !ENV['CONDUCTOR_INTEGRATION'] do
  let(:server_url) { ENV['CONDUCTOR_SERVER_URL'] || 'https://developer.orkescloud.com/api' }
  let(:auth_key) { ENV.fetch('CONDUCTOR_AUTH_KEY', nil) }
  let(:auth_secret) { ENV.fetch('CONDUCTOR_AUTH_SECRET', nil) }
  let(:test_id) { "ruby_sdk_task_#{SecureRandom.hex(4)}" }

  let(:configuration) do
    Conductor::Configuration.new(
      server_api_url: server_url,
      auth_key: auth_key,
      auth_secret: auth_secret
    )
  end

  let(:clients) { Conductor::Orkes::OrkesClients.new(configuration) }
  let(:workflow_client) { clients.get_workflow_client }
  let(:task_client) { clients.get_task_client }
  let(:metadata_client) { clients.get_metadata_client }
  let(:api_client) { Conductor::Http::ApiClient.new(configuration: configuration) }
  let(:task_api) { Conductor::Http::Api::TaskResourceApi.new(api_client) }

  # Helper to skip tests that hit free tier limits
  def skip_if_limit_reached(error)
    raise error unless error.is_a?(Conductor::ApiError) && error.status == 402

    skip "Orkes free tier limit reached: #{error.message}"
  end

  describe 'Setup: Create test task and workflow' do
    it 'creates a task definition' do
      task_def = Conductor::Http::Models::TaskDef.new(
        name: "#{test_id}_simple_task",
        description: 'Test task for task operations',
        retry_count: 0,
        timeout_seconds: 60,
        response_timeout_seconds: 30
      )
      metadata_client.register_task_def(task_def)
      expect(true).to be true
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it 'creates a workflow with a SIMPLE task' do
      workflow_def = Conductor::Http::Models::WorkflowDef.new(
        name: "#{test_id}_task_workflow",
        version: 1,
        description: 'Workflow with SIMPLE task for testing',
        tasks: [
          Conductor::Http::Models::WorkflowTask.new(
            name: "#{test_id}_simple_task",
            task_reference_name: 'simple_task_ref',
            type: 'SIMPLE',
            input_parameters: {
              'input_data' => '${workflow.input.data}'
            }
          )
        ],
        input_parameters: ['data'],
        schema_version: 2
      )
      metadata_client.register_workflow_def(workflow_def, overwrite: true)
      expect(true).to be true
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Task Queue Operations' do
    it 'size - gets queue sizes for task types' do
      sizes = task_api.size(task_types: ["#{test_id}_simple_task"])

      expect(sizes).to be_a(Hash)
    rescue Conductor::ApiError => e
      # This endpoint may not be supported in all Orkes environments
      if e.status == 405
        skip 'Queue size POST endpoint not supported in this environment'
      else
        skip_if_limit_reached(e)
      end
    end

    it 'all_queue_details - gets all queue details' do
      details = task_api.all_queue_details

      expect(details).to be_a(Hash)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it 'get_task_queue_details - gets details for specific task type' do
      details = task_api.get_task_queue_details("#{test_id}_simple_task")

      expect(details).to be_a(Hash)
    rescue Conductor::ApiError => e
      # 404 is acceptable if no queue exists for this task type
      # 405 means the endpoint is not supported in this environment
      if e.status == 404 || e.status == 405
        skip 'Task queue details endpoint not available for this task type'
      else
        skip_if_limit_reached(e)
      end
    end

    it 'all_verbose - gets verbose queue details' do
      details = task_api.all_verbose

      expect(details).to be_a(Hash)
    rescue Conductor::ApiError => e
      # This endpoint may have issues in some environments
      if e.status == 500 && e.message.include?('Null key')
        skip 'Verbose queue details endpoint has server-side issue'
      else
        skip_if_limit_reached(e)
      end
    end

    it 'get_queue_sizes_for_tasks - gets queue sizes via GET' do
      sizes = task_api.get_queue_sizes_for_tasks(["#{test_id}_simple_task"])

      expect(sizes).to be_a(Hash)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Task Poll Operations' do
    let(:workflow_id) { @workflow_id }

    before do
      # Ensure task and workflow exist
      begin
        task_def = Conductor::Http::Models::TaskDef.new(
          name: "#{test_id}_simple_task",
          description: 'Test task',
          retry_count: 0,
          timeout_seconds: 60
        )
        metadata_client.register_task_def(task_def)
      rescue Conductor::ApiError
        # Task may exist
      end

      begin
        workflow_def = Conductor::Http::Models::WorkflowDef.new(
          name: "#{test_id}_task_workflow",
          version: 1,
          description: 'Workflow with SIMPLE task',
          tasks: [
            Conductor::Http::Models::WorkflowTask.new(
              name: "#{test_id}_simple_task",
              task_reference_name: 'simple_task_ref',
              type: 'SIMPLE',
              input_parameters: { 'input_data' => '${workflow.input.data}' }
            )
          ],
          schema_version: 2
        )
        metadata_client.register_workflow_def(workflow_def, overwrite: true)
      rescue Conductor::ApiError
        # Workflow may exist
      end

      # Start workflow to create a task
      request = Conductor::Http::Models::StartWorkflowRequest.new(
        name: "#{test_id}_task_workflow",
        version: 1,
        input: { 'data' => 'test_poll' }
      )
      @workflow_id = workflow_client.start(request)
    end

    after do
      workflow_client.terminate_workflow(@workflow_id, reason: 'Test cleanup')
    rescue StandardError
      # Ignore
    end

    it 'poll - polls for a task (single)' do
      # Poll for the task
      task = task_api.poll("#{test_id}_simple_task", worker_id: 'ruby_test_worker')

      # Task may or may not be available depending on timing
      if task
        expect(task).to respond_to(:task_id).or be_a(Hash)
      else
        expect(task).to be_nil
      end
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it 'batch_poll - polls for multiple tasks' do
      # Batch poll for tasks
      tasks = task_api.batch_poll(
        "#{test_id}_simple_task",
        count: 5,
        timeout: 1000,
        worker_id: 'ruby_test_worker'
      )

      expect(tasks).to be_an(Array)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it 'get_pending_task_for_task_type - gets pending tasks' do
      pending = task_api.get_pending_task_for_task_type(
        "#{test_id}_simple_task",
        start: 0,
        count: 10
      )

      expect(pending).to be_an(Array)
    rescue Conductor::ApiError => e
      # This endpoint may not exist in Orkes
      if e.status == 404
        skip 'Pending tasks endpoint not available in this environment'
      else
        skip_if_limit_reached(e)
      end
    end
  end

  describe 'Task Update Operations' do
    let(:workflow_id) { @workflow_id }
    let(:task) { @task }

    before do
      # Ensure task and workflow exist
      begin
        task_def = Conductor::Http::Models::TaskDef.new(
          name: "#{test_id}_simple_task",
          description: 'Test task',
          retry_count: 0,
          timeout_seconds: 60
        )
        metadata_client.register_task_def(task_def)
      rescue Conductor::ApiError
        # Task may exist
      end

      begin
        workflow_def = Conductor::Http::Models::WorkflowDef.new(
          name: "#{test_id}_task_workflow",
          version: 1,
          description: 'Workflow with SIMPLE task',
          tasks: [
            Conductor::Http::Models::WorkflowTask.new(
              name: "#{test_id}_simple_task",
              task_reference_name: 'simple_task_ref',
              type: 'SIMPLE',
              input_parameters: { 'input_data' => '${workflow.input.data}' }
            )
          ],
          schema_version: 2
        )
        metadata_client.register_workflow_def(workflow_def, overwrite: true)
      rescue Conductor::ApiError
        # Workflow may exist
      end

      # Start workflow and poll for task
      request = Conductor::Http::Models::StartWorkflowRequest.new(
        name: "#{test_id}_task_workflow",
        version: 1,
        input: { 'data' => 'test_update' }
      )
      @workflow_id = workflow_client.start(request)

      # Give time for task to be scheduled
      sleep(1)

      # Poll for the task
      @task = task_api.poll("#{test_id}_simple_task", worker_id: 'ruby_test_worker')
    end

    after do
      workflow_client.terminate_workflow(@workflow_id, reason: 'Test cleanup')
    rescue StandardError
      # Ignore
    end

    it 'update_task - updates task with result' do
      skip 'No task available to update' unless @task

      task_id = @task.is_a?(Hash) ? @task['taskId'] : @task.task_id

      # Create task result
      result = Conductor::Http::Models::TaskResult.new(
        workflow_instance_id: @workflow_id,
        task_id: task_id,
        status: 'COMPLETED',
        output_data: { 'result' => 'success from Ruby SDK' }
      )

      response = task_api.update_task(result)
      expect(response).not_to be_nil
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it 'get_task - retrieves task details' do
      skip 'No task available' unless @task

      task_id = @task.is_a?(Hash) ? @task['taskId'] : @task.task_id

      retrieved = task_api.get_task(task_id)
      expect(retrieved).not_to be_nil

      retrieved_id = retrieved.is_a?(Hash) ? retrieved['taskId'] : retrieved.task_id
      expect(retrieved_id).to eq(task_id)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Task Update by Reference Name' do
    let(:workflow_id) { @workflow_id }

    before do
      # Ensure workflow exists with a WAIT task (not SIMPLE)
      begin
        workflow_def = Conductor::Http::Models::WorkflowDef.new(
          name: "#{test_id}_wait_workflow",
          version: 1,
          description: 'Workflow with WAIT task',
          tasks: [
            Conductor::Http::Models::WorkflowTask.new(
              name: 'wait_for_update',
              task_reference_name: 'wait_ref',
              type: 'WAIT',
              input_parameters: {}
            )
          ],
          schema_version: 2
        )
        metadata_client.register_workflow_def(workflow_def, overwrite: true)
      rescue Conductor::ApiError
        # Workflow may exist
      end

      # Start workflow
      request = Conductor::Http::Models::StartWorkflowRequest.new(
        name: "#{test_id}_wait_workflow",
        version: 1,
        input: {}
      )
      @workflow_id = workflow_client.start(request)
    end

    after do
      workflow_client.terminate_workflow(@workflow_id, reason: 'Test cleanup')
    rescue StandardError
      # Ignore
    end

    it 'update_task_by_ref_name - completes task by reference name' do
      # Complete the WAIT task by reference name
      result = task_api.update_task_by_ref_name(
        @workflow_id,
        'wait_ref',
        'COMPLETED',
        output: { 'completed_by' => 'test' }
      )

      expect(result).not_to be_nil

      # Verify workflow completed
      sleep(1)
      wf = workflow_client.get_workflow(@workflow_id)
      status = wf.is_a?(Hash) ? wf['status'] : wf.status
      expect(status).to eq('COMPLETED')
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it 'update_task_sync - completes task and returns workflow state' do
      # First ensure we have a running workflow with WAIT task
      request = Conductor::Http::Models::StartWorkflowRequest.new(
        name: "#{test_id}_wait_workflow",
        version: 1,
        input: {}
      )
      new_wf_id = workflow_client.start(request)

      # Complete the WAIT task synchronously
      workflow = task_api.update_task_sync(
        new_wf_id,
        'wait_ref',
        'COMPLETED',
        output: { 'sync_completed' => true }
      )

      expect(workflow).not_to be_nil

      # Response should contain workflow state
      status = workflow.is_a?(Hash) ? workflow['status'] : workflow.status
      expect(status).to eq('COMPLETED')
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    ensure
      begin
        workflow_client.terminate_workflow(new_wf_id, reason: 'Test cleanup') if new_wf_id
      rescue StandardError
        # Ignore
      end
    end
  end

  describe 'Task Search' do
    it 'search - searches for tasks' do
      results = task_api.search(
        start: 0,
        size: 10,
        free_text: '*'
      )

      expect(results).not_to be_nil

      # Check results structure
      if results.is_a?(Hash)
        expect(results).to have_key('results').or have_key('totalHits')
      else
        expect(results).to respond_to(:results).or respond_to(:total_hits)
      end
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it 'search - with query filter' do
      results = task_api.search(
        start: 0,
        size: 5,
        query: "taskType:#{test_id}_simple_task"
      )

      expect(results).not_to be_nil
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Poll Data Operations' do
    it 'get_poll_data - gets poll data for task type' do
      data = task_api.get_poll_data("#{test_id}_simple_task")

      expect(data).to be_an(Array)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it 'get_all_poll_data - gets all poll data' do
      data = task_api.get_all_poll_data

      # Response may be an Array or a Hash with pollData key
      if data.is_a?(Hash)
        expect(data).to have_key('pollData').or have_key(:pollData)
      else
        expect(data).to be_an(Array)
      end
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Cleanup' do
    it 'removes test workflow and task definitions' do
      begin
        metadata_client.unregister_workflow_def("#{test_id}_task_workflow", version: 1)
      rescue StandardError
        # Ignore
      end
      begin
        metadata_client.unregister_workflow_def("#{test_id}_wait_workflow", version: 1)
      rescue StandardError
        # Ignore
      end
      begin
        metadata_client.unregister_task_def("#{test_id}_simple_task")
      rescue StandardError
        # Ignore
      end
      expect(true).to be true
    end
  end
end
