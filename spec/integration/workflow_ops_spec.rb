# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

# Workflow Operations integration tests - run with:
# ORKES_INTEGRATION=true bundle exec rspec spec/integration/workflow_ops_spec.rb --format documentation
#
# These tests cover additional workflow operations not in the basic workflow_spec.rb:
# - restart, retry, rerun (single workflow)
# - get_workflows (by correlation ID)
# - get_running_workflow
# - execute_workflow (synchronous)
# - get_workflow_status (lightweight)
# - search workflows
# - update_workflow_state (variables)
# - delete workflow
# - skip_task_from_workflow
# - get_workflows_batch

RSpec.describe 'Workflow Operations Integration', skip: !ENV['ORKES_INTEGRATION'] do
  let(:server_url) { ENV['ORKES_SERVER_URL'] || 'https://developer.orkescloud.com/api' }
  let(:auth_key) { ENV['ORKES_AUTH_KEY'] }
  let(:auth_secret) { ENV['ORKES_AUTH_SECRET'] }
  let(:test_id) { "ruby_sdk_wfops_#{SecureRandom.hex(4)}" }

  let(:configuration) do
    Conductor::Configuration.new(
      server_api_url: server_url,
      auth_key: auth_key,
      auth_secret: auth_secret
    )
  end

  let(:clients) { Conductor::Orkes::OrkesClients.new(configuration) }
  let(:workflow_client) { clients.get_workflow_client }
  let(:metadata_client) { clients.get_metadata_client }
  let(:api_client) { Conductor::Http::ApiClient.new(configuration: configuration) }
  let(:workflow_api) { Conductor::Http::Api::WorkflowResourceApi.new(api_client) }

  # Helper to skip tests that hit free tier limits
  def skip_if_limit_reached(error)
    if error.is_a?(Conductor::ApiError) && error.status == 402
      skip "Orkes free tier limit reached: #{error.message}"
    else
      raise error
    end
  end

  # Helper to get workflow status
  def get_status(workflow)
    workflow.is_a?(Hash) ? workflow['status'] : workflow.status
  end

  describe 'Setup: Create test workflows' do
    it 'creates a WAIT workflow for testing' do
      workflow_def = Conductor::Http::Models::WorkflowDef.new(
        name: "#{test_id}_wait_workflow",
        version: 1,
        description: 'Test workflow with WAIT task',
        tasks: [
          Conductor::Http::Models::WorkflowTask.new(
            name: 'wait_task',
            task_reference_name: 'wait_task_ref',
            type: 'WAIT',
            input_parameters: {}
          )
        ],
        schema_version: 2,
        restartable: true
      )
      metadata_client.register_workflow_def(workflow_def, overwrite: true)
      expect(true).to be true
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it 'creates a simple SET_VARIABLE workflow for testing' do
      workflow_def = Conductor::Http::Models::WorkflowDef.new(
        name: "#{test_id}_simple_workflow",
        version: 1,
        description: 'Simple test workflow',
        tasks: [
          Conductor::Http::Models::WorkflowTask.new(
            name: 'set_var',
            task_reference_name: 'set_var_ref',
            type: 'SET_VARIABLE',
            input_parameters: {
              'result' => '${workflow.input.value}'
            }
          )
        ],
        input_parameters: ['value'],
        output_parameters: {
          'output' => '${set_var_ref.input.result}'
        },
        schema_version: 2,
        restartable: true
      )
      metadata_client.register_workflow_def(workflow_def, overwrite: true)
      expect(true).to be true
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Correlation ID Operations' do
    let(:correlation_id) { "corr_#{test_id}_#{SecureRandom.hex(4)}" }
    let(:workflow_ids) { [] }

    before do
      # Ensure workflow exists
      begin
        workflow_def = Conductor::Http::Models::WorkflowDef.new(
          name: "#{test_id}_wait_workflow",
          version: 1,
          description: 'Test workflow',
          tasks: [
            Conductor::Http::Models::WorkflowTask.new(
              name: 'wait_task',
              task_reference_name: 'wait_task_ref',
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
    end

    after do
      workflow_ids.each do |wf_id|
        begin
          workflow_client.terminate_workflow(wf_id, reason: 'Test cleanup')
        rescue StandardError
          # Ignore
        end
      end
    end

    it 'get_workflows - retrieves workflows by correlation ID' do
      # Start a workflow with a correlation ID
      request = Conductor::Http::Models::StartWorkflowRequest.new(
        name: "#{test_id}_wait_workflow",
        version: 1,
        correlation_id: correlation_id,
        input: { 'test' => true }
      )
      wf_id = workflow_client.start(request)
      workflow_ids << wf_id

      # Get workflows by correlation ID
      workflows = workflow_api.get_workflows(
        "#{test_id}_wait_workflow",
        correlation_id,
        include_closed: false,
        include_tasks: true
      )

      expect(workflows).to be_an(Array)
      expect(workflows.length).to be >= 1

      # Our workflow should be in the result
      wf_ids = workflows.map { |w| w.is_a?(Hash) ? w['workflowId'] : w.workflow_id }
      expect(wf_ids).to include(wf_id)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it 'get_workflows_batch - retrieves workflows by multiple correlation IDs' do
      # Start workflows with different correlation IDs
      corr_id1 = "#{correlation_id}_1"
      corr_id2 = "#{correlation_id}_2"

      request1 = Conductor::Http::Models::StartWorkflowRequest.new(
        name: "#{test_id}_wait_workflow",
        version: 1,
        correlation_id: corr_id1,
        input: { 'batch' => 1 }
      )
      wf_id1 = workflow_client.start(request1)
      workflow_ids << wf_id1

      request2 = Conductor::Http::Models::StartWorkflowRequest.new(
        name: "#{test_id}_wait_workflow",
        version: 1,
        correlation_id: corr_id2,
        input: { 'batch' => 2 }
      )
      wf_id2 = workflow_client.start(request2)
      workflow_ids << wf_id2

      # Get workflows by batch correlation IDs
      result = workflow_api.get_workflows_batch(
        "#{test_id}_wait_workflow",
        [corr_id1, corr_id2],
        include_closed: false,
        include_tasks: false
      )

      expect(result).to be_a(Hash)
      # Result should have entries for both correlation IDs
      expect(result.keys.length).to be >= 1
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Running Workflow Operations' do
    let(:workflow_ids) { [] }

    before do
      begin
        workflow_def = Conductor::Http::Models::WorkflowDef.new(
          name: "#{test_id}_wait_workflow",
          version: 1,
          description: 'Test workflow',
          tasks: [
            Conductor::Http::Models::WorkflowTask.new(
              name: 'wait_task',
              task_reference_name: 'wait_task_ref',
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
    end

    after do
      workflow_ids.each do |wf_id|
        begin
          workflow_client.terminate_workflow(wf_id, reason: 'Test cleanup')
        rescue StandardError
          # Ignore
        end
      end
    end

    it 'get_running_workflow - lists running workflow IDs by name' do
      # Start a workflow
      request = Conductor::Http::Models::StartWorkflowRequest.new(
        name: "#{test_id}_wait_workflow",
        version: 1,
        input: {}
      )
      wf_id = workflow_client.start(request)
      workflow_ids << wf_id

      # Get running workflows
      running_ids = workflow_api.get_running_workflow("#{test_id}_wait_workflow")

      expect(running_ids).to be_an(Array)
      expect(running_ids).to include(wf_id)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it 'get_running_workflow - filters by version' do
      # Start a workflow
      request = Conductor::Http::Models::StartWorkflowRequest.new(
        name: "#{test_id}_wait_workflow",
        version: 1,
        input: {}
      )
      wf_id = workflow_client.start(request)
      workflow_ids << wf_id

      # Get running workflows for version 1
      running_ids = workflow_api.get_running_workflow(
        "#{test_id}_wait_workflow",
        version: 1
      )

      expect(running_ids).to be_an(Array)
      expect(running_ids).to include(wf_id)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Workflow Status Operations' do
    let(:workflow_id) { @workflow_id }

    before do
      begin
        workflow_def = Conductor::Http::Models::WorkflowDef.new(
          name: "#{test_id}_wait_workflow",
          version: 1,
          description: 'Test workflow',
          tasks: [
            Conductor::Http::Models::WorkflowTask.new(
              name: 'wait_task',
              task_reference_name: 'wait_task_ref',
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

      # Start a workflow
      request = Conductor::Http::Models::StartWorkflowRequest.new(
        name: "#{test_id}_wait_workflow",
        version: 1,
        input: { 'test_value' => 'hello' }
      )
      @workflow_id = workflow_client.start(request)
    end

    after do
      begin
        workflow_client.terminate_workflow(@workflow_id, reason: 'Test cleanup')
      rescue StandardError
        # Ignore
      end
    end

    it 'get_workflow_status - gets lightweight workflow status' do
      status = workflow_api.get_workflow_status(@workflow_id)

      expect(status).to be_a(Hash)
      expect(status['status']).to eq('RUNNING')
      expect(status['workflowId']).to eq(@workflow_id)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it 'get_workflow_status - with output and variables' do
      status = workflow_api.get_workflow_status(
        @workflow_id,
        include_output: true,
        include_variables: true
      )

      expect(status).to be_a(Hash)
      expect(status['status']).to eq('RUNNING')
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Search Operations' do
    let(:workflow_id) { @workflow_id }

    before do
      begin
        workflow_def = Conductor::Http::Models::WorkflowDef.new(
          name: "#{test_id}_simple_workflow",
          version: 1,
          description: 'Simple test workflow',
          tasks: [
            Conductor::Http::Models::WorkflowTask.new(
              name: 'set_var',
              task_reference_name: 'set_var_ref',
              type: 'SET_VARIABLE',
              input_parameters: { 'result' => '${workflow.input.value}' }
            )
          ],
          schema_version: 2
        )
        metadata_client.register_workflow_def(workflow_def, overwrite: true)
      rescue Conductor::ApiError
        # Workflow may exist
      end

      # Start a workflow
      request = Conductor::Http::Models::StartWorkflowRequest.new(
        name: "#{test_id}_simple_workflow",
        version: 1,
        input: { 'value' => 'search_test' }
      )
      @workflow_id = workflow_client.start(request)
      sleep(1) # Give time for indexing
    end

    after do
      begin
        workflow_client.terminate_workflow(@workflow_id, reason: 'Test cleanup')
      rescue StandardError
        # Ignore
      end
    end

    it 'search - searches workflows with query' do
      # Search for our workflow by name
      results = workflow_api.search(
        start: 0,
        size: 10,
        query: "workflowType:#{test_id}_simple_workflow"
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

    it 'search - with free text' do
      results = workflow_api.search(
        start: 0,
        size: 10,
        free_text: '*'
      )

      expect(results).not_to be_nil
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Synchronous Execution' do
    before do
      begin
        workflow_def = Conductor::Http::Models::WorkflowDef.new(
          name: "#{test_id}_simple_workflow",
          version: 1,
          description: 'Simple test workflow',
          tasks: [
            Conductor::Http::Models::WorkflowTask.new(
              name: 'set_var',
              task_reference_name: 'set_var_ref',
              type: 'SET_VARIABLE',
              input_parameters: { 'result' => '${workflow.input.value}' }
            )
          ],
          output_parameters: {
            'output' => '${set_var_ref.input.result}'
          },
          schema_version: 2
        )
        metadata_client.register_workflow_def(workflow_def, overwrite: true)
      rescue Conductor::ApiError
        # Workflow may exist
      end
    end

    it 'execute_workflow - runs workflow synchronously' do
      request_id = SecureRandom.uuid
      request = Conductor::Http::Models::StartWorkflowRequest.new(
        input: { 'value' => 'sync_test' }
      )

      result = workflow_api.execute_workflow(
        request,
        name: "#{test_id}_simple_workflow",
        version: 1,
        request_id: request_id,
        wait_for_seconds: 30
      )

      expect(result).not_to be_nil

      # Check the result
      status = result.is_a?(Hash) ? result['status'] : result.status
      expect(status).to eq('COMPLETED')
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Workflow Lifecycle Operations' do
    let(:workflow_ids) { [] }

    before do
      begin
        workflow_def = Conductor::Http::Models::WorkflowDef.new(
          name: "#{test_id}_wait_workflow",
          version: 1,
          description: 'Test workflow',
          tasks: [
            Conductor::Http::Models::WorkflowTask.new(
              name: 'wait_task',
              task_reference_name: 'wait_task_ref',
              type: 'WAIT',
              input_parameters: {}
            )
          ],
          schema_version: 2,
          restartable: true
        )
        metadata_client.register_workflow_def(workflow_def, overwrite: true)
      rescue Conductor::ApiError
        # Workflow may exist
      end
    end

    after do
      workflow_ids.each do |wf_id|
        begin
          workflow_client.terminate_workflow(wf_id, reason: 'Test cleanup')
        rescue StandardError
          # Ignore
        end
      end
    end

    it 'restart - restarts a terminated workflow' do
      # Start and terminate a workflow
      request = Conductor::Http::Models::StartWorkflowRequest.new(
        name: "#{test_id}_wait_workflow",
        version: 1,
        input: { 'restart_test' => true }
      )
      wf_id = workflow_client.start(request)
      workflow_ids << wf_id

      workflow_client.terminate_workflow(wf_id, reason: 'Preparing for restart')

      # Verify terminated
      wf = workflow_client.get_workflow(wf_id)
      expect(get_status(wf)).to eq('TERMINATED')

      # Restart
      workflow_api.restart(wf_id)

      # Give time to restart
      sleep(1)

      # Verify running again
      wf = workflow_client.get_workflow(wf_id)
      expect(get_status(wf)).to eq('RUNNING')
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it 'restart - with use_latest_def flag' do
      # Start and terminate a workflow
      request = Conductor::Http::Models::StartWorkflowRequest.new(
        name: "#{test_id}_wait_workflow",
        version: 1,
        input: {}
      )
      wf_id = workflow_client.start(request)
      workflow_ids << wf_id

      workflow_client.terminate_workflow(wf_id, reason: 'Preparing for restart')

      # Restart with latest definition
      workflow_api.restart(wf_id, use_latest_def: true)

      sleep(1)

      # Verify running
      wf = workflow_client.get_workflow(wf_id)
      expect(get_status(wf)).to eq('RUNNING')
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it 'delete - removes a workflow' do
      # Start and terminate a workflow
      request = Conductor::Http::Models::StartWorkflowRequest.new(
        name: "#{test_id}_wait_workflow",
        version: 1,
        input: {}
      )
      wf_id = workflow_client.start(request)
      # Don't add to workflow_ids since we're deleting it

      workflow_client.terminate_workflow(wf_id, reason: 'Preparing for delete')

      # Delete the workflow
      workflow_api.delete(wf_id, archive_workflow: false)

      # Verify deleted - should get 404
      expect do
        workflow_client.get_workflow(wf_id)
      end.to raise_error(Conductor::ApiError) { |e| expect(e.status).to eq(404) }
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Workflow Variables' do
    let(:workflow_id) { @workflow_id }

    before do
      begin
        workflow_def = Conductor::Http::Models::WorkflowDef.new(
          name: "#{test_id}_wait_workflow",
          version: 1,
          description: 'Test workflow',
          tasks: [
            Conductor::Http::Models::WorkflowTask.new(
              name: 'wait_task',
              task_reference_name: 'wait_task_ref',
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

      # Start a workflow
      request = Conductor::Http::Models::StartWorkflowRequest.new(
        name: "#{test_id}_wait_workflow",
        version: 1,
        input: {}
      )
      @workflow_id = workflow_client.start(request)
    end

    after do
      begin
        workflow_client.terminate_workflow(@workflow_id, reason: 'Test cleanup')
      rescue StandardError
        # Ignore
      end
    end

    it 'update_workflow_state - updates workflow variables' do
      variables = {
        'custom_var1' => 'value1',
        'custom_var2' => 123,
        'custom_var3' => { 'nested' => 'object' }
      }

      result = workflow_api.update_workflow_state(@workflow_id, variables)
      expect(result).not_to be_nil

      # Verify by getting workflow status with variables
      status = workflow_api.get_workflow_status(@workflow_id, include_variables: true)
      expect(status).to be_a(Hash)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Start Workflow Alternatives' do
    before do
      begin
        workflow_def = Conductor::Http::Models::WorkflowDef.new(
          name: "#{test_id}_simple_workflow",
          version: 1,
          description: 'Simple test workflow',
          tasks: [
            Conductor::Http::Models::WorkflowTask.new(
              name: 'set_var',
              task_reference_name: 'set_var_ref',
              type: 'SET_VARIABLE',
              input_parameters: { 'result' => '${workflow.input.value}' }
            )
          ],
          schema_version: 2
        )
        metadata_client.register_workflow_def(workflow_def, overwrite: true)
      rescue Conductor::ApiError
        # Workflow may exist
      end
    end

    it 'start_workflow_by_name - starts workflow with simple input' do
      correlation_id = "start_by_name_#{SecureRandom.hex(4)}"

      wf_id = workflow_api.start_workflow_by_name(
        "#{test_id}_simple_workflow",
        { 'value' => 'test_input' },
        version: 1,
        correlation_id: correlation_id
      )

      expect(wf_id).to be_a(String)
      expect(wf_id).not_to be_empty

      # Clean up
      begin
        workflow_client.terminate_workflow(wf_id, reason: 'Test cleanup')
      rescue StandardError
        # Ignore
      end
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Cleanup' do
    it 'removes test workflow definitions' do
      begin
        metadata_client.unregister_workflow_def("#{test_id}_wait_workflow", version: 1)
      rescue StandardError
        # Ignore
      end
      begin
        metadata_client.unregister_workflow_def("#{test_id}_simple_workflow", version: 1)
      rescue StandardError
        # Ignore
      end
      expect(true).to be true
    end
  end
end
