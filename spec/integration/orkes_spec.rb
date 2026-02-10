# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

# Orkes integration tests - run with:
# ORKES_INTEGRATION=true bundle exec rspec spec/integration/orkes_spec.rb --format documentation
#
# These tests require Orkes Conductor credentials set via environment variables:
# - ORKES_SERVER_URL (defaults to https://developer.orkescloud.com/api)
# - ORKES_AUTH_KEY
# - ORKES_AUTH_SECRET
#
# Note: Some tests may be skipped on free tier accounts due to resource limits.

RSpec.describe 'Orkes Integration', skip: !ENV['ORKES_INTEGRATION'] do
  let(:server_url) { ENV['ORKES_SERVER_URL'] || 'https://developer.orkescloud.com/api' }
  let(:auth_key) { ENV['ORKES_AUTH_KEY'] }
  let(:auth_secret) { ENV['ORKES_AUTH_SECRET'] }
  let(:test_id) { "ruby_sdk_test_#{SecureRandom.hex(4)}" }

  let(:configuration) do
    Conductor::Configuration.new(
      server_api_url: server_url,
      auth_key: auth_key,
      auth_secret: auth_secret
    )
  end

  let(:clients) { Conductor::Orkes::OrkesClients.new(configuration) }

  # Helper to skip tests that hit free tier limits
  def skip_if_limit_reached(error)
    if error.is_a?(Conductor::ApiError) && error.status == 402
      skip "Orkes free tier limit reached: #{error.message}"
    else
      raise error
    end
  end

  describe 'OrkesClients factory' do
    it 'creates all client types successfully' do
      expect(clients.get_workflow_client).to be_a(Conductor::Client::WorkflowClient)
      expect(clients.get_task_client).to be_a(Conductor::Client::TaskClient)
      expect(clients.get_metadata_client).to be_a(Conductor::Client::MetadataClient)
      expect(clients.get_scheduler_client).to be_a(Conductor::Client::SchedulerClient)
      expect(clients.get_authorization_client).to be_a(Conductor::Client::AuthorizationClient)
      expect(clients.get_secret_client).to be_a(Conductor::Client::SecretClient)
      expect(clients.get_integration_client).to be_a(Conductor::Client::IntegrationClient)
      expect(clients.get_prompt_client).to be_a(Conductor::Client::PromptClient)
      expect(clients.get_schema_client).to be_a(Conductor::Client::SchemaClient)
      expect(clients.get_workflow_executor).to be_a(Conductor::Workflow::WorkflowExecutor)
    end
  end

  describe 'SecretClient' do
    let(:secret_client) { clients.get_secret_client }
    let(:secret_key) { "#{test_id}_secret" }
    let(:secret_value) { "test_secret_value_#{SecureRandom.hex(8)}" }

    after do
      # Clean up: delete the test secret if it exists
      begin
        secret_client.delete_secret(secret_key)
      rescue StandardError
        # Ignore errors during cleanup
      end
    end

    it 'performs CRUD operations on secrets' do
      # Create
      secret_client.put_secret(secret_key, secret_value)

      # Verify it exists
      exists = secret_client.secret_exists(secret_key)
      expect(exists).to be true

      # List secrets should include our key
      secrets = secret_client.list_all_secret_names
      expect(secrets).to include(secret_key)

      # Get secret (note: Orkes may return masked value or the actual value depending on permissions)
      retrieved = secret_client.get_secret(secret_key)
      expect(retrieved).not_to be_nil

      # Delete
      secret_client.delete_secret(secret_key)

      # Verify deleted
      exists_after = secret_client.secret_exists(secret_key)
      expect(exists_after).to be false
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it 'handles secret tags' do
      # Create secret first
      secret_client.put_secret(secret_key, secret_value)

      # Set tags
      tags = [
        Conductor::Http::Models::TagObject.new(
          key: 'environment', type: Conductor::Http::Models::TagType::METADATA, value: 'test'
        ),
        Conductor::Http::Models::TagObject.new(
          key: 'team', type: Conductor::Http::Models::TagType::METADATA, value: 'sdk'
        )
      ]
      secret_client.set_secret_tags(tags, secret_key)

      # Get tags
      retrieved_tags = secret_client.get_secret_tags(secret_key)
      expect(retrieved_tags).to be_an(Array)
      tag_keys = retrieved_tags.map { |t| t.is_a?(Hash) ? t['key'] : t.key }
      expect(tag_keys).to include('environment')

      # Delete tags
      secret_client.delete_secret_tags(tags, secret_key)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'SchemaClient' do
    let(:schema_client) { clients.get_schema_client }

    it 'lists all schemas' do
      # This should work even on free tier
      all_schemas = schema_client.get_all_schemas
      expect(all_schemas).to be_an(Array)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it 'performs CRUD operations on schemas' do
      schema_name = "#{test_id}_schema"

      begin
        # Create schema
        schema = Conductor::Http::Models::SchemaDef.new(
          name: schema_name,
          version: 1,
          type: Conductor::Http::Models::SchemaType::JSON,
          data: {
            'type' => 'object',
            'properties' => {
              'name' => { 'type' => 'string' },
              'age' => { 'type' => 'integer' }
            },
            'required' => ['name']
          }
        )
        schema_client.register_schema(schema)

        # Get schema to verify it was created
        retrieved = schema_client.get_schema(schema_name, 1)
        expect(retrieved).not_to be_nil
        expect(retrieved.name).to eq(schema_name) if retrieved.respond_to?(:name)

        # Delete by version (Note: Orkes API may return 500 but still delete the schema)
        begin
          schema_client.delete_schema(schema_name, 1)
        rescue Conductor::ApiError => e
          # Orkes API sometimes returns 500 even when delete succeeds - verify it's gone
          unless e.status == 500
            skip_if_limit_reached(e)
            raise e
          end
        end

        # Verify deletion - should get 404
        expect do
          schema_client.get_schema(schema_name, 1)
        end.to raise_error(Conductor::ApiError) { |e| expect(e.status).to eq(404) }
      rescue Conductor::ApiError => e
        skip_if_limit_reached(e)
      end
    end
  end

  describe 'AuthorizationClient' do
    let(:auth_client) { clients.get_authorization_client }

    describe 'token operations' do
      it 'gets user info from current token' do
        user_info = auth_client.get_user_info_from_token
        expect(user_info).not_to be_nil
      end
    end

    describe 'role operations' do
      it 'lists all roles' do
        roles = auth_client.list_all_roles
        expect(roles).to be_an(Array)
      end

      it 'lists system roles' do
        system_roles = auth_client.list_system_roles
        expect(system_roles).not_to be_nil
      end

      it 'lists available permissions' do
        permissions = auth_client.list_available_permissions
        expect(permissions).not_to be_nil
      end
    end

    describe 'user operations' do
      it 'lists users' do
        users = auth_client.list_users
        expect(users).to be_an(Array)
      end
    end

    describe 'group operations' do
      it 'lists groups' do
        groups = auth_client.list_groups
        expect(groups).to be_an(Array)
      end
    end

    describe 'application operations' do
      let(:app_name) { "#{test_id}_app" }
      let(:created_app_id) { @created_app_id }

      after do
        # Clean up created application
        if @created_app_id
          begin
            auth_client.delete_application(@created_app_id)
          rescue StandardError
            # Ignore cleanup errors
          end
        end
      end

      it 'performs CRUD operations on applications' do
        # Create application
        request = Conductor::Http::Models::CreateOrUpdateApplicationRequest.new(
          name: app_name
        )
        app = auth_client.create_application(request)
        expect(app).not_to be_nil

        # Store ID for cleanup (handle both hash and object responses)
        @created_app_id = app.is_a?(Hash) ? app['id'] : app.id

        # List applications
        apps = auth_client.list_applications
        expect(apps).to be_an(Array)
        app_ids = apps.map { |a| a.is_a?(Hash) ? a['id'] : a.id }
        expect(app_ids).to include(@created_app_id)

        # Get application
        retrieved = auth_client.get_application(@created_app_id)
        expect(retrieved).not_to be_nil

        # Delete application
        auth_client.delete_application(@created_app_id)
        @created_app_id = nil # Don't try to delete again in after block
      rescue Conductor::ApiError => e
        skip_if_limit_reached(e)
      end

      it 'lists existing applications' do
        apps = auth_client.list_applications
        expect(apps).to be_an(Array)
      end
    end
  end

  describe 'WorkflowClient with Orkes' do
    let(:workflow_client) { clients.get_workflow_client }
    let(:metadata_client) { clients.get_metadata_client }
    let(:workflow_name) { "#{test_id}_workflow" }

    after do
      # Clean up workflow definition
      begin
        metadata_client.unregister_workflow_def(workflow_name, version: 1)
      rescue StandardError
        # Ignore cleanup errors
      end
    end

    it 'registers and executes a simple workflow' do
      # Create a simple workflow definition
      workflow_def = Conductor::Http::Models::WorkflowDef.new(
        name: workflow_name,
        version: 1,
        description: 'Ruby SDK Orkes integration test workflow',
        tasks: [
          Conductor::Http::Models::WorkflowTask.new(
            name: 'set_variable_task',
            task_reference_name: 'set_var_ref',
            type: 'SET_VARIABLE',
            input_parameters: {
              'result' => '${workflow.input.message}'
            }
          )
        ],
        input_parameters: ['message'],
        output_parameters: {
          'output' => '${set_var_ref.input.result}'
        },
        schema_version: 2,
        restartable: true,
        workflow_status_listener_enabled: false
      )

      # Register workflow
      metadata_client.register_workflow_def(workflow_def, overwrite: true)

      # Start workflow
      workflow_id = workflow_client.start(
        Conductor::Http::Models::StartWorkflowRequest.new(
          name: workflow_name,
          version: 1,
          input: { 'message' => 'Hello from Ruby SDK!' }
        )
      )
      expect(workflow_id).not_to be_nil
      expect(workflow_id).to be_a(String)

      # Wait a moment for execution
      sleep(1)

      # Get workflow status
      workflow = workflow_client.get_workflow(workflow_id, include_tasks: true)
      expect(workflow).not_to be_nil
      status = workflow.is_a?(Hash) ? workflow['status'] : workflow.status
      expect(['RUNNING', 'COMPLETED']).to include(status)

      # Terminate if still running
      if status == 'RUNNING'
        workflow_client.terminate_workflow(workflow_id, reason: 'Test cleanup')
      end
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it 'retrieves existing workflow definitions' do
      # This test just verifies we can list workflows (doesn't create new ones)
      workflows = metadata_client.get_all_workflow_defs
      expect(workflows).to be_an(Array)
    end
  end

  describe 'Workflow DSL with Orkes' do
    let(:workflow_executor) { clients.get_workflow_executor }
    let(:metadata_client) { clients.get_metadata_client }
    let(:workflow_name) { "#{test_id}_dsl_workflow" }

    after do
      begin
        metadata_client.unregister_workflow_def(workflow_name, version: 1)
      rescue StandardError
        # Ignore cleanup errors
      end
    end

    it 'creates and registers a workflow using the DSL' do
      # Build workflow using DSL
      workflow = Conductor::Workflow::ConductorWorkflow.new(executor: workflow_executor)
      workflow.name = workflow_name
      workflow.version = 1
      workflow.description = 'Ruby SDK DSL test on Orkes'

      # Add a simple set variable task
      set_var = Conductor::Workflow::SetVariableTask.new('set_greeting')
      set_var.input('greeting', '${workflow.input.name}')
      workflow.add(set_var)

      # Register the workflow
      workflow.register(overwrite: true)

      # Verify it was registered
      retrieved = metadata_client.get_workflow_def(workflow_name, version: 1)
      expect(retrieved).not_to be_nil
      name = retrieved.is_a?(Hash) ? retrieved['name'] : retrieved.name
      expect(name).to eq(workflow_name)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'IntegrationClient' do
    let(:integration_client) { clients.get_integration_client }

    it 'lists available integrations' do
      # This just verifies the API call works (may return empty array)
      integrations = integration_client.get_integrations
      expect(integrations).to be_an(Array)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it 'gets integration provider definitions' do
      # This just verifies the API call works (may return empty array)
      providers = integration_client.get_integration_provider_defs
      expect(providers).to be_an(Array)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'PromptClient' do
    let(:prompt_client) { clients.get_prompt_client }

    it 'lists available prompts' do
      # This just verifies the API call works (may return empty array)
      prompts = prompt_client.get_prompts
      expect(prompts).to be_an(Array)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end
end
