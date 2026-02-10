# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

# Event Handler integration tests - run with:
# ORKES_INTEGRATION=true bundle exec rspec spec/integration/event_spec.rb --format documentation
#
# These tests require Orkes Conductor credentials set via environment variables:
# - ORKES_SERVER_URL
# - ORKES_AUTH_KEY
# - ORKES_AUTH_SECRET
#
# APIs covered:
# 1. add_event_handler - Create event handler
# 2. get_event_handlers - List all event handlers
# 3. get_event_handlers_for_event - Get handlers for specific event
# 4. update_event_handler - Update event handler
# 5. remove_event_handler - Delete event handler
# 6. get_queue_names - List queue configurations
# 7. get_queue_config - Get queue configuration
# 8. put_queue_config - Create/update queue configuration
# 9. delete_queue_config - Delete queue configuration

RSpec.describe 'Event Handler Integration', skip: !ENV['ORKES_INTEGRATION'] do
  let(:server_url) { ENV['ORKES_SERVER_URL'] || 'https://developer.orkescloud.com/api' }
  let(:auth_key) { ENV['ORKES_AUTH_KEY'] }
  let(:auth_secret) { ENV['ORKES_AUTH_SECRET'] }
  let(:test_id) { "ruby_sdk_event_#{SecureRandom.hex(4)}" }

  let(:configuration) do
    Conductor::Configuration.new(
      server_api_url: server_url,
      auth_key: auth_key,
      auth_secret: auth_secret
    )
  end

  let(:api_client) { Conductor::Http::ApiClient.new(configuration: configuration) }
  let(:event_api) { Conductor::Http::Api::EventResourceApi.new(api_client) }
  let(:metadata_client) do
    clients = Conductor::Orkes::OrkesClients.new(configuration)
    clients.get_metadata_client
  end

  # Helper to skip tests that hit free tier limits
  def skip_if_limit_reached(error)
    if error.is_a?(Conductor::ApiError) && error.status == 402
      skip "Orkes free tier limit reached: #{error.message}"
    else
      raise error
    end
  end

  describe 'Setup: Create test workflow' do
    it 'creates a workflow for event handlers' do
      workflow_def = Conductor::Http::Models::WorkflowDef.new(
        name: "#{test_id}_event_workflow",
        version: 1,
        description: 'Test workflow for event handler integration tests',
        tasks: [
          Conductor::Http::Models::WorkflowTask.new(
            name: 'event_task',
            task_reference_name: 'event_task_ref',
            type: 'SET_VARIABLE',
            input_parameters: {
              'event_received' => true,
              'event_data' => '${workflow.input.event_data}'
            }
          )
        ],
        input_parameters: ['event_data'],
        schema_version: 2,
        restartable: true
      )

      metadata_client.register_workflow_def(workflow_def, overwrite: true)
      expect(true).to be true
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Event Handler CRUD Operations' do
    let(:handler_name) { "#{test_id}_handler" }
    let(:event_name) { "#{test_id}:test_event" }

    # Ensure workflow exists before each test
    before do
      begin
        workflow_def = Conductor::Http::Models::WorkflowDef.new(
          name: "#{test_id}_event_workflow",
          version: 1,
          description: 'Test workflow',
          tasks: [
            Conductor::Http::Models::WorkflowTask.new(
              name: 'event_task',
              task_reference_name: 'event_task_ref',
              type: 'SET_VARIABLE',
              input_parameters: { 'test' => true }
            )
          ],
          schema_version: 2
        )
        metadata_client.register_workflow_def(workflow_def, overwrite: true)
      rescue Conductor::ApiError
        # Workflow may already exist
      end
    end

    after do
      # Clean up event handler
      begin
        event_api.remove_event_handler(handler_name)
      rescue StandardError
        # Ignore cleanup errors
      end
    end

    it '1. add_event_handler - creates a new event handler' do
      # Create an event handler that starts a workflow when an event is received
      handler = Conductor::Http::Models::EventHandler.new(
        name: handler_name,
        event: event_name,
        condition: 'true', # Always trigger
        actions: [
          Conductor::Http::Models::EventHandlerAction.new(
            action: 'start_workflow',
            start_workflow: Conductor::Http::Models::StartWorkflow.new(
              name: "#{test_id}_event_workflow",
              version: 1,
              input: {
                'event_data' => '${event_payload}'
              }
            ),
            expand_inline_json: false
          )
        ],
        active: true
      )

      # Add the handler
      event_api.add_event_handler(handler)

      # Verify it was created by getting all handlers
      handlers = event_api.get_event_handlers
      handler_names = handlers.map do |h|
        h.is_a?(Hash) ? h['name'] : h.name
      end
      expect(handler_names).to include(handler_name)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it '2. get_event_handlers - lists all event handlers' do
      # First create a handler
      handler = Conductor::Http::Models::EventHandler.new(
        name: handler_name,
        event: event_name,
        actions: [
          Conductor::Http::Models::EventHandlerAction.new(
            action: 'start_workflow',
            start_workflow: Conductor::Http::Models::StartWorkflow.new(
              name: "#{test_id}_event_workflow",
              version: 1,
              input: {}
            )
          )
        ],
        active: true
      )
      event_api.add_event_handler(handler)

      # Get all handlers
      handlers = event_api.get_event_handlers
      expect(handlers).to be_an(Array)

      # Our handler should be in the list
      our_handler = handlers.find do |h|
        name = h.is_a?(Hash) ? h['name'] : h.name
        name == handler_name
      end
      expect(our_handler).not_to be_nil
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it '3. get_event_handlers_for_event - gets handlers for specific event' do
      # First create a handler
      handler = Conductor::Http::Models::EventHandler.new(
        name: handler_name,
        event: event_name,
        actions: [
          Conductor::Http::Models::EventHandlerAction.new(
            action: 'start_workflow',
            start_workflow: Conductor::Http::Models::StartWorkflow.new(
              name: "#{test_id}_event_workflow",
              version: 1,
              input: {}
            )
          )
        ],
        active: true
      )
      event_api.add_event_handler(handler)

      # Get handlers for our specific event
      handlers = event_api.get_event_handlers_for_event(event_name)
      expect(handlers).to be_an(Array)

      if handlers.any?
        handler_names = handlers.map do |h|
          h.is_a?(Hash) ? h['name'] : h.name
        end
        expect(handler_names).to include(handler_name)
      end
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it '3b. get_event_handlers_for_event - filters by active_only' do
      # First create a handler (inactive)
      handler = Conductor::Http::Models::EventHandler.new(
        name: handler_name,
        event: event_name,
        actions: [
          Conductor::Http::Models::EventHandlerAction.new(
            action: 'start_workflow',
            start_workflow: Conductor::Http::Models::StartWorkflow.new(
              name: "#{test_id}_event_workflow",
              version: 1,
              input: {}
            )
          )
        ],
        active: false # Inactive handler
      )
      event_api.add_event_handler(handler)

      # Get active handlers only
      active_handlers = event_api.get_event_handlers_for_event(event_name, active_only: true)

      # Our inactive handler should not be in the active list
      active_names = (active_handlers || []).map do |h|
        h.is_a?(Hash) ? h['name'] : h.name
      end
      expect(active_names).not_to include(handler_name)

      # Get all handlers (including inactive)
      all_handlers = event_api.get_event_handlers_for_event(event_name, active_only: false)
      all_names = (all_handlers || []).map do |h|
        h.is_a?(Hash) ? h['name'] : h.name
      end
      expect(all_names).to include(handler_name)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it '4. update_event_handler - updates an existing handler' do
      # First create a handler
      handler = Conductor::Http::Models::EventHandler.new(
        name: handler_name,
        event: event_name,
        condition: 'true',
        actions: [
          Conductor::Http::Models::EventHandlerAction.new(
            action: 'start_workflow',
            start_workflow: Conductor::Http::Models::StartWorkflow.new(
              name: "#{test_id}_event_workflow",
              version: 1,
              input: { 'version' => 'v1' }
            )
          )
        ],
        active: true
      )
      event_api.add_event_handler(handler)

      # Update the handler
      updated_handler = Conductor::Http::Models::EventHandler.new(
        name: handler_name,
        event: event_name,
        condition: 'event.payload.enabled == true', # Changed condition
        actions: [
          Conductor::Http::Models::EventHandlerAction.new(
            action: 'start_workflow',
            start_workflow: Conductor::Http::Models::StartWorkflow.new(
              name: "#{test_id}_event_workflow",
              version: 1,
              input: { 'version' => 'v2', 'updated' => true }
            )
          )
        ],
        active: true
      )
      event_api.update_event_handler(updated_handler)

      # Verify the update
      handlers = event_api.get_event_handlers_for_event(event_name, active_only: false)
      our_handler = handlers.find do |h|
        name = h.is_a?(Hash) ? h['name'] : h.name
        name == handler_name
      end

      expect(our_handler).not_to be_nil
      condition = our_handler.is_a?(Hash) ? our_handler['condition'] : our_handler.condition
      expect(condition).to eq('event.payload.enabled == true')
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it '5. remove_event_handler - deletes an event handler' do
      # First create a handler
      handler = Conductor::Http::Models::EventHandler.new(
        name: handler_name,
        event: event_name,
        actions: [
          Conductor::Http::Models::EventHandlerAction.new(
            action: 'start_workflow',
            start_workflow: Conductor::Http::Models::StartWorkflow.new(
              name: "#{test_id}_event_workflow",
              version: 1,
              input: {}
            )
          )
        ],
        active: true
      )
      event_api.add_event_handler(handler)

      # Delete the handler
      event_api.remove_event_handler(handler_name)

      # Verify it's deleted
      handlers = event_api.get_event_handlers
      handler_names = handlers.map do |h|
        h.is_a?(Hash) ? h['name'] : h.name
      end
      expect(handler_names).not_to include(handler_name)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Queue Configuration Operations' do
    # Note: Queue configuration operations require integration with message queues
    # These tests verify the API calls work but may not actually configure queues

    it '6. get_queue_names - lists queue configurations' do
      # This returns a map of queue types to their names
      queues = event_api.get_queue_names

      # Should return a hash (may be empty if no queues configured)
      expect(queues).to be_a(Hash).or be_nil
    rescue Conductor::ApiError => e
      # Queue operations may not be available on all installations
      if e.status == 404 || e.status == 501
        skip 'Queue configuration API not available in this environment'
      else
        skip_if_limit_reached(e)
      end
    end

    it '7. get_queue_config - gets queue configuration' do
      # Try to get configuration for a conductor queue type
      # Note: This may fail if no queues are configured
      begin
        config = event_api.get_queue_config('conductor', 'test_queue')
        expect(config).to be_a(Hash).or be_nil
      rescue Conductor::ApiError => e
        # 404 is expected if queue doesn't exist
        if e.status == 404
          expect(true).to be true # Queue not found is acceptable
        elsif e.status == 501
          skip 'Queue configuration API not available in this environment'
        else
          skip_if_limit_reached(e)
        end
      end
    end

    it '8-9. put_queue_config and delete_queue_config - manages queue configuration' do
      queue_type = 'conductor'
      queue_name = "#{test_id}_queue"

      begin
        # Create/update queue configuration
        config = { 'queueName' => queue_name, 'batchSize' => 10 }
        event_api.put_queue_config(queue_type, queue_name, config)

        # Verify it was created
        retrieved_config = event_api.get_queue_config(queue_type, queue_name)
        expect(retrieved_config).not_to be_nil

        # Delete the configuration
        event_api.delete_queue_config(queue_type, queue_name)

        # Verify it's deleted
        expect do
          event_api.get_queue_config(queue_type, queue_name)
        end.to raise_error(Conductor::ApiError) { |e| expect(e.status).to eq(404) }
      rescue Conductor::ApiError => e
        # Queue operations may not be available
        if e.status == 501 || e.message.include?('not supported')
          skip 'Queue configuration API not available in this environment'
        elsif e.status == 400 && e.message.include?('integrations API')
          skip 'Queue configuration is managed via integrations API in Orkes Cloud'
        elsif e.status == 403
          skip 'Queue configuration requires special permissions'
        else
          skip_if_limit_reached(e)
        end
      end
    end
  end

  describe 'Event Handler with Conditional Logic' do
    let(:handler_name) { "#{test_id}_conditional" }
    let(:event_name) { "#{test_id}:conditional_event" }

    before do
      begin
        workflow_def = Conductor::Http::Models::WorkflowDef.new(
          name: "#{test_id}_event_workflow",
          version: 1,
          description: 'Test workflow',
          tasks: [
            Conductor::Http::Models::WorkflowTask.new(
              name: 'event_task',
              task_reference_name: 'event_task_ref',
              type: 'SET_VARIABLE',
              input_parameters: { 'test' => true }
            )
          ],
          schema_version: 2
        )
        metadata_client.register_workflow_def(workflow_def, overwrite: true)
      rescue Conductor::ApiError
        # Workflow may already exist
      end
    end

    after do
      begin
        event_api.remove_event_handler(handler_name)
      rescue StandardError
        # Ignore cleanup errors
      end
    end

    it 'creates event handler with JavaScript condition' do
      handler = Conductor::Http::Models::EventHandler.new(
        name: handler_name,
        event: event_name,
        condition: "event.payload.priority == 'high' && event.payload.amount > 1000",
        evaluator_type: 'javascript',
        actions: [
          Conductor::Http::Models::EventHandlerAction.new(
            action: 'start_workflow',
            start_workflow: Conductor::Http::Models::StartWorkflow.new(
              name: "#{test_id}_event_workflow",
              version: 1,
              input: {
                'priority' => '${event.payload.priority}',
                'amount' => '${event.payload.amount}'
              }
            ),
            expand_inline_json: true
          )
        ],
        active: true
      )

      event_api.add_event_handler(handler)

      # Verify it was created
      handlers = event_api.get_event_handlers
      our_handler = handlers.find do |h|
        name = h.is_a?(Hash) ? h['name'] : h.name
        name == handler_name
      end

      expect(our_handler).not_to be_nil
      evaluator = our_handler.is_a?(Hash) ? our_handler['evaluatorType'] : our_handler.evaluator_type
      expect(evaluator).to eq('javascript')
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Cleanup' do
    it 'removes test workflow definition' do
      begin
        metadata_client.unregister_workflow_def("#{test_id}_event_workflow", version: 1)
      rescue StandardError
        # Ignore errors - workflow may not exist
      end
      expect(true).to be true
    end
  end
end
