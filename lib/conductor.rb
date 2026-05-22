# frozen_string_literal: true

require_relative 'conductor/version'
require_relative 'conductor/configuration'
require_relative 'conductor/configuration/authentication_settings'
require_relative 'conductor/exceptions'
require_relative 'conductor/http/rest_client'
require_relative 'conductor/http/api_client'
require_relative 'conductor/http/models/base_model'
require_relative 'conductor/http/models/token'
require_relative 'conductor/http/models/task_result_status'
require_relative 'conductor/http/models/task'
require_relative 'conductor/http/models/task_result'
require_relative 'conductor/http/models/workflow_status_constants'
require_relative 'conductor/http/models/start_workflow_request'
require_relative 'conductor/http/models/workflow_task'
require_relative 'conductor/http/models/workflow_def'
require_relative 'conductor/http/models/workflow'
require_relative 'conductor/http/models/task_def'
require_relative 'conductor/http/models/task_exec_log'
require_relative 'conductor/http/models/rerun_workflow_request'
require_relative 'conductor/http/models/skip_task_request'
require_relative 'conductor/http/models/bulk_response'
require_relative 'conductor/http/models/poll_data'
require_relative 'conductor/http/models/workflow_state_update'
require_relative 'conductor/http/models/workflow_test_request'
require_relative 'conductor/http/models/search_result'
require_relative 'conductor/http/models/event_handler'
require_relative 'conductor/http/models/workflow_schedule'
# Orkes-specific models
require_relative 'conductor/http/models/tag_object'
require_relative 'conductor/http/models/subject_ref'
require_relative 'conductor/http/models/target_ref'
require_relative 'conductor/http/models/authorization_request'
require_relative 'conductor/http/models/permission'
require_relative 'conductor/http/models/role'
require_relative 'conductor/http/models/group'
require_relative 'conductor/http/models/conductor_user'
require_relative 'conductor/http/models/conductor_application'
require_relative 'conductor/http/models/upsert_user_request'
require_relative 'conductor/http/models/upsert_group_request'
require_relative 'conductor/http/models/create_or_update_application_request'
require_relative 'conductor/http/models/create_or_update_role_request'
require_relative 'conductor/http/models/generate_token_request'
require_relative 'conductor/http/models/authentication_config'
require_relative 'conductor/http/models/prompt_template'
require_relative 'conductor/http/models/prompt_template_test_request'
require_relative 'conductor/http/models/schema_def'
require_relative 'conductor/http/models/integration'
require_relative 'conductor/http/models/integration_api'
require_relative 'conductor/http/models/integration_update'
require_relative 'conductor/http/models/integration_api_update'
# OSS API resources
require_relative 'conductor/http/api/workflow_resource_api'
require_relative 'conductor/http/api/task_resource_api'
require_relative 'conductor/http/api/metadata_resource_api'
require_relative 'conductor/http/api/workflow_bulk_resource_api'
require_relative 'conductor/http/api/event_resource_api'
require_relative 'conductor/http/api/scheduler_resource_api'
# Orkes API resources
require_relative 'conductor/http/api/secret_resource_api'
require_relative 'conductor/http/api/application_resource_api'
require_relative 'conductor/http/api/user_resource_api'
require_relative 'conductor/http/api/group_resource_api'
require_relative 'conductor/http/api/authorization_resource_api'
require_relative 'conductor/http/api/role_resource_api'
require_relative 'conductor/http/api/token_resource_api'
require_relative 'conductor/http/api/gateway_auth_resource_api'
require_relative 'conductor/http/api/schema_resource_api'
require_relative 'conductor/http/api/integration_resource_api'
require_relative 'conductor/http/api/prompt_resource_api'
# OSS Clients
require_relative 'conductor/client/workflow_client'
require_relative 'conductor/client/task_client'
require_relative 'conductor/client/metadata_client'
require_relative 'conductor/client/scheduler_client'
# Orkes Clients
require_relative 'conductor/client/secret_client'
require_relative 'conductor/client/authorization_client'
require_relative 'conductor/client/schema_client'
require_relative 'conductor/client/integration_client'
require_relative 'conductor/client/prompt_client'
# Orkes-specific models
require_relative 'conductor/orkes/models/metadata_tag'
require_relative 'conductor/orkes/models/rate_limit_tag'
require_relative 'conductor/orkes/models/access_key'
require_relative 'conductor/orkes/models/granted_permission'
# Orkes factory
require_relative 'conductor/orkes/orkes_clients'
# Worker Infrastructure
require_relative 'conductor/worker/events/conductor_event'
require_relative 'conductor/worker/events/task_runner_events'
require_relative 'conductor/worker/events/workflow_events'
require_relative 'conductor/worker/events/http_events'
require_relative 'conductor/worker/events/sync_event_dispatcher'
require_relative 'conductor/worker/events/global_dispatcher'
require_relative 'conductor/worker/events/listeners'
require_relative 'conductor/worker/events/listener_registry'
require_relative 'conductor/worker/task_context'
require_relative 'conductor/worker/task_in_progress'
require_relative 'conductor/worker/worker_config'
require_relative 'conductor/worker/worker_registry'
require_relative 'conductor/worker/worker'
require_relative 'conductor/worker/task_runner'
require_relative 'conductor/worker/task_handler'
require_relative 'conductor/worker/telemetry/metrics_collector'
require_relative 'conductor/worker/task_definition_registrar'
# Optional executors - these are lazy-loaded when their dependencies are available
# require_relative 'conductor/worker/ractor_task_runner'  # Requires Ruby 3.1+
# require_relative 'conductor/worker/fiber_executor'      # Requires async gem
# require_relative 'conductor/worker/telemetry/prometheus_backend'  # Requires prometheus-client gem

# Workflow DSL
require_relative 'conductor/workflow/task_type'
require_relative 'conductor/workflow/timeout_policy'
require_relative 'conductor/workflow/workflow_executor'
# LLM/AI helpers (used by DSL)
require_relative 'conductor/workflow/llm/chat_message'
require_relative 'conductor/workflow/llm/tool_call'
require_relative 'conductor/workflow/llm/tool_spec'
require_relative 'conductor/workflow/llm/embedding_model'
# Workflow DSL
require_relative 'conductor/workflow/dsl/output_ref'
require_relative 'conductor/workflow/dsl/input_ref'
require_relative 'conductor/workflow/dsl/task_ref'
require_relative 'conductor/workflow/dsl/workflow_builder'
require_relative 'conductor/workflow/dsl/parallel_builder'
require_relative 'conductor/workflow/dsl/switch_builder'
require_relative 'conductor/workflow/dsl/workflow_definition'

# Main Conductor module
# Provides convenience methods for configuration
module Conductor
  class << self
    # Get or set the default configuration
    # @return [Conductor::Configuration] The default configuration
    def config
      @config ||= Conductor::Configuration.new
    end

    # Set the default configuration
    # @param [Conductor::Configuration] configuration The configuration to set
    attr_writer :config

    # Configure Conductor with a block
    # @yield [Conductor::Configuration] The configuration object
    # @example
    #   Conductor.configure do |config|
    #     config.server_url = 'http://localhost:7001/api'
    #     config.authentication_settings = Conductor::Configuration::AuthenticationSettings.new(
    #       key_id: 'my_key',
    #       key_secret: 'my_secret'
    #     )
    #   end
    def configure
      yield(config) if block_given?
    end

    # Define a workflow using the new Ruby-idiomatic DSL
    # @param name [Symbol, String] Workflow name
    # @param version [Integer, nil] Workflow version (optional)
    # @param description [String, nil] Workflow description (optional)
    # @param executor [WorkflowExecutor, nil] Optional executor for .register() and .execute()
    # @yield Block containing workflow definition
    # @return [Workflow::Dsl::WorkflowDefinition] The workflow definition
    # @example
    #   workflow = Conductor.workflow :order_processing, version: 1, executor: executor do
    #     user = simple :get_user, user_id: wf[:user_id]
    #     order = simple :create_order, user_email: user[:email]
    #
    #     parallel do
    #       simple :send_confirmation, email: user[:email]
    #       simple :update_inventory, order_id: order[:id]
    #     end
    #
    #     output order_id: order[:id], status: 'created'
    #   end
    #
    #   workflow.register(overwrite: true)
    #   result = workflow.execute(input: { user_id: 123 })
    def workflow(name, version: nil, description: nil, executor: nil, &block)
      builder = Workflow::Dsl::WorkflowBuilder.new(
        name.to_s,
        version: version,
        description: description,
        executor: executor
      )
      builder.instance_eval(&block)
      Workflow::Dsl::WorkflowDefinition.new(builder, executor: executor)
    end
  end
end
