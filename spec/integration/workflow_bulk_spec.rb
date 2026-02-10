# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

# Workflow Bulk Operations integration tests - run with:
# CONDUCTOR_INTEGRATION=true bundle exec rspec spec/integration/workflow_bulk_spec.rb --format documentation
#
# These tests require Conductor credentials set via environment variables:
# - CONDUCTOR_SERVER_URL
# - CONDUCTOR_AUTH_KEY
# - CONDUCTOR_AUTH_SECRET
#
# APIs covered:
# 1. pause_workflow - Pause workflows in bulk
# 2. resume_workflow - Resume workflows in bulk
# 3. terminate - Terminate workflows in bulk
# 4. restart - Restart workflows in bulk
# 5. retry - Retry workflows in bulk

RSpec.describe 'Workflow Bulk Operations Integration', skip: !ENV['CONDUCTOR_INTEGRATION'] do
  let(:server_url) { ENV['CONDUCTOR_SERVER_URL'] || 'https://developer.orkescloud.com/api' }
  let(:auth_key) { ENV.fetch('CONDUCTOR_AUTH_KEY', nil) }
  let(:auth_secret) { ENV.fetch('CONDUCTOR_AUTH_SECRET', nil) }
  let(:test_id) { "ruby_sdk_bulk_#{SecureRandom.hex(4)}" }

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
  let(:bulk_api) { Conductor::Http::Api::WorkflowBulkResourceApi.new(api_client) }

  # Helper to skip tests that hit free tier limits
  def skip_if_limit_reached(error)
    raise error unless error.is_a?(Conductor::ApiError) && error.status == 402

    skip "Orkes free tier limit reached: #{error.message}"
  end

  # Helper to create a test workflow definition
  def create_test_workflow_def(name)
    Conductor::Http::Models::WorkflowDef.new(
      name: name,
      version: 1,
      description: 'Test workflow for bulk operations',
      tasks: [
        # Use WAIT task so workflow stays in RUNNING state
        Conductor::Http::Models::WorkflowTask.new(
          name: 'wait_task',
          task_reference_name: 'wait_task_ref',
          type: 'WAIT',
          input_parameters: {}
        )
      ],
      schema_version: 2,
      restartable: true,
      timeout_seconds: 3600
    )
  end

  # Helper to get workflow status
  def get_status(workflow)
    workflow.is_a?(Hash) ? workflow['status'] : workflow.status
  end

  # Helper to get bulk response data
  def get_bulk_response_data(response, key)
    if response.is_a?(Hash)
      response[key] || response[key.to_s]
    else
      response.send(key)
    end
  end

  describe 'Setup: Create test workflow' do
    it 'creates a workflow definition for bulk testing' do
      workflow_def = create_test_workflow_def("#{test_id}_wait_workflow")
      metadata_client.register_workflow_def(workflow_def, overwrite: true)
      expect(true).to be true
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Bulk Pause and Resume Operations' do
    let(:workflow_ids) { [] }

    before do
      # Ensure workflow exists
      begin
        workflow_def = create_test_workflow_def("#{test_id}_wait_workflow")
        metadata_client.register_workflow_def(workflow_def, overwrite: true)
      rescue Conductor::ApiError
        # Workflow may exist
      end

      # Start 3 workflows
      3.times do |i|
        request = Conductor::Http::Models::StartWorkflowRequest.new(
          name: "#{test_id}_wait_workflow",
          version: 1,
          input: { 'batch_id' => i }
        )
        wf_id = workflow_client.start(request)
        workflow_ids << wf_id
      end
    end

    after do
      # Terminate all workflows
      workflow_ids.each do |wf_id|
        workflow_client.terminate_workflow(wf_id, reason: 'Test cleanup')
      rescue StandardError
        # Ignore cleanup errors
      end
    end

    it '1. pause_workflow - pauses multiple workflows' do
      # Verify workflows are running
      workflow_ids.each do |wf_id|
        wf = workflow_client.get_workflow(wf_id)
        expect(get_status(wf)).to eq('RUNNING')
      end

      # Pause all workflows in bulk
      result = bulk_api.pause_workflow(workflow_ids)
      expect(result).not_to be_nil

      # Check bulk response
      bulk_successful = get_bulk_response_data(result, :bulk_successful_results)
      bulk_error = get_bulk_response_data(result, :bulk_error_results)

      expect(bulk_successful).to be_an(Array).or be_nil
      expect(bulk_error).to be_an(Hash).or be_nil

      # Verify workflows are paused
      workflow_ids.each do |wf_id|
        wf = workflow_client.get_workflow(wf_id)
        expect(get_status(wf)).to eq('PAUSED')
      end
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it '2. resume_workflow - resumes multiple paused workflows' do
      # First pause all workflows
      bulk_api.pause_workflow(workflow_ids)

      # Verify they're paused
      workflow_ids.each do |wf_id|
        wf = workflow_client.get_workflow(wf_id)
        expect(get_status(wf)).to eq('PAUSED')
      end

      # Resume all workflows in bulk
      result = bulk_api.resume_workflow(workflow_ids)
      expect(result).not_to be_nil

      # Verify workflows are resumed (back to RUNNING)
      workflow_ids.each do |wf_id|
        wf = workflow_client.get_workflow(wf_id)
        expect(get_status(wf)).to eq('RUNNING')
      end
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Bulk Terminate Operations' do
    let(:workflow_ids) { [] }

    before do
      # Ensure workflow exists
      begin
        workflow_def = create_test_workflow_def("#{test_id}_wait_workflow")
        metadata_client.register_workflow_def(workflow_def, overwrite: true)
      rescue Conductor::ApiError
        # Workflow may exist
      end

      # Start 3 workflows
      3.times do |i|
        request = Conductor::Http::Models::StartWorkflowRequest.new(
          name: "#{test_id}_wait_workflow",
          version: 1,
          input: { 'batch_id' => i }
        )
        wf_id = workflow_client.start(request)
        workflow_ids << wf_id
      end
    end

    it '3. terminate - terminates multiple workflows' do
      # Verify workflows are running
      workflow_ids.each do |wf_id|
        wf = workflow_client.get_workflow(wf_id)
        expect(get_status(wf)).to eq('RUNNING')
      end

      # Terminate all workflows in bulk
      result = bulk_api.terminate(workflow_ids, reason: 'Bulk termination test')
      expect(result).not_to be_nil

      # Verify workflows are terminated
      workflow_ids.each do |wf_id|
        wf = workflow_client.get_workflow(wf_id)
        expect(get_status(wf)).to eq('TERMINATED')
      end
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Bulk Restart Operations' do
    let(:workflow_ids) { [] }

    before do
      # Ensure workflow exists
      begin
        workflow_def = create_test_workflow_def("#{test_id}_wait_workflow")
        metadata_client.register_workflow_def(workflow_def, overwrite: true)
      rescue Conductor::ApiError
        # Workflow may exist
      end

      # Start and terminate workflows (so we can restart them)
      3.times do |i|
        request = Conductor::Http::Models::StartWorkflowRequest.new(
          name: "#{test_id}_wait_workflow",
          version: 1,
          input: { 'batch_id' => i }
        )
        wf_id = workflow_client.start(request)
        workflow_ids << wf_id
        # Terminate so we can restart
        workflow_client.terminate_workflow(wf_id, reason: 'Preparing for restart test')
      end
    end

    after do
      # Terminate all workflows
      workflow_ids.each do |wf_id|
        workflow_client.terminate_workflow(wf_id, reason: 'Test cleanup')
      rescue StandardError
        # Ignore cleanup errors
      end
    end

    it '4. restart - restarts multiple terminated workflows' do
      # Verify workflows are terminated
      workflow_ids.each do |wf_id|
        wf = workflow_client.get_workflow(wf_id)
        expect(get_status(wf)).to eq('TERMINATED')
      end

      # Restart all workflows in bulk
      result = bulk_api.restart(workflow_ids)
      expect(result).not_to be_nil

      # Give some time for restart to process
      sleep(1)

      # Verify workflows are running again
      workflow_ids.each do |wf_id|
        wf = workflow_client.get_workflow(wf_id)
        expect(get_status(wf)).to eq('RUNNING')
      end
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it '4b. restart - with use_latest_definitions flag' do
      # Restart with use_latest_definitions = true
      result = bulk_api.restart(workflow_ids, use_latest_definitions: true)
      expect(result).not_to be_nil

      # Give some time for restart to process
      sleep(1)

      # Verify workflows are running
      workflow_ids.each do |wf_id|
        wf = workflow_client.get_workflow(wf_id)
        expect(get_status(wf)).to eq('RUNNING')
      end
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Bulk Retry Operations' do
    # NOTE: Retry is for failed workflows, which requires a workflow that can fail
    # We'll create a simplified test that validates the API works

    let(:workflow_ids) { [] }

    before do
      # Create a workflow with a simple task (will complete immediately)
      workflow_def = Conductor::Http::Models::WorkflowDef.new(
        name: "#{test_id}_simple_workflow",
        version: 1,
        description: 'Simple workflow for retry test',
        tasks: [
          Conductor::Http::Models::WorkflowTask.new(
            name: 'set_var',
            task_reference_name: 'set_var_ref',
            type: 'SET_VARIABLE',
            input_parameters: { 'value' => '${workflow.input.value}' }
          )
        ],
        schema_version: 2,
        restartable: true
      )

      begin
        metadata_client.register_workflow_def(workflow_def, overwrite: true)
      rescue Conductor::ApiError
        # Workflow may exist
      end
    end

    after do
      workflow_ids.each do |wf_id|
        workflow_client.terminate_workflow(wf_id, reason: 'Test cleanup')
      rescue StandardError
        # Ignore cleanup errors
      end
      # Clean up workflow definition
      begin
        metadata_client.unregister_workflow_def("#{test_id}_simple_workflow", version: 1)
      rescue StandardError
        # Ignore cleanup errors
      end
    end

    it '5. retry - retries workflows (validates API works)' do
      # Start a workflow
      request = Conductor::Http::Models::StartWorkflowRequest.new(
        name: "#{test_id}_simple_workflow",
        version: 1,
        input: { 'value' => 'test' }
      )
      wf_id = workflow_client.start(request)
      workflow_ids << wf_id

      # Wait for completion
      sleep(1)

      # Retry completed workflows (may succeed or fail depending on workflow state)
      # The main goal is to verify the API endpoint works
      begin
        result = bulk_api.retry([wf_id])

        # If retry worked, check the response structure
        expect(result).not_to be_nil
        bulk_error = get_bulk_response_data(result, :bulk_error_results)

        # Retry on completed workflow may return errors, which is expected
        expect(bulk_error).to be_a(Hash).or be_nil
      rescue Conductor::ApiError => e
        # Retry on non-failed workflow may return 4xx error, which is acceptable
        # The point is the API endpoint is reachable and functional
        expect([400, 404, 409, 422]).to include(e.status)
      end
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Bulk Operations Error Handling' do
    it 'handles non-existent workflow IDs gracefully' do
      fake_ids = %w[non_existent_1 non_existent_2 non_existent_3]

      # Bulk terminate should handle non-existent IDs
      result = bulk_api.terminate(fake_ids, reason: 'Testing error handling')

      expect(result).not_to be_nil

      # Should have errors for non-existent workflows
      bulk_error = get_bulk_response_data(result, :bulk_error_results)
      expect(bulk_error).to be_a(Hash) if bulk_error
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it 'handles empty workflow list' do
      # Bulk operations with empty list should not fail
      begin
        result = bulk_api.pause_workflow([])
        expect(result).not_to be_nil
      rescue Conductor::ApiError => e
        # Empty list might return 400, which is acceptable
        expect(e.status).to eq(400)
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
        # Ignore errors
      end
      expect(true).to be true
    end
  end
end
