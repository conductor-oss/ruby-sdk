# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # Workflow definition model for registering workflows with Conductor
      class WorkflowDef < BaseModel
        SWAGGER_TYPES = {
          name: 'String',
          description: 'String',
          version: 'Integer',
          tasks: 'Array<WorkflowTask>',
          input_parameters: 'Array<String>',
          output_parameters: 'Hash<String, Object>',
          failure_workflow: 'String',
          schema_version: 'Integer',
          restartable: 'Boolean',
          workflow_status_listener_enabled: 'Boolean',
          workflow_status_listener_sink: 'String',
          owner_email: 'String',
          timeout_policy: 'String',
          timeout_seconds: 'Integer',
          variables: 'Hash<String, Object>',
          input_template: 'Hash<String, Object>'
        }.freeze

        ATTRIBUTE_MAP = {
          name: :name,
          description: :description,
          version: :version,
          tasks: :tasks,
          input_parameters: :inputParameters,
          output_parameters: :outputParameters,
          failure_workflow: :failureWorkflow,
          schema_version: :schemaVersion,
          restartable: :restartable,
          workflow_status_listener_enabled: :workflowStatusListenerEnabled,
          workflow_status_listener_sink: :workflowStatusListenerSink,
          owner_email: :ownerEmail,
          timeout_policy: :timeoutPolicy,
          timeout_seconds: :timeoutSeconds,
          variables: :variables,
          input_template: :inputTemplate
        }.freeze

        attr_accessor :name, :description, :version, :tasks, :input_parameters,
                      :output_parameters, :failure_workflow, :schema_version,
                      :restartable, :workflow_status_listener_enabled,
                      :workflow_status_listener_sink, :owner_email, :timeout_policy,
                      :timeout_seconds, :variables, :input_template

        def initialize(params = {})
          @name = params[:name]
          @description = params[:description]
          @version = params[:version]
          @tasks = params[:tasks] || []
          @input_parameters = params[:input_parameters] || []
          @output_parameters = params[:output_parameters] || {}
          @failure_workflow = params[:failure_workflow]
          @schema_version = params[:schema_version] || 2
          @restartable = params[:restartable].nil? ? true : params[:restartable]
          @workflow_status_listener_enabled = params[:workflow_status_listener_enabled] || false
          @workflow_status_listener_sink = params[:workflow_status_listener_sink]
          @owner_email = params[:owner_email]
          @timeout_policy = params[:timeout_policy]
          @timeout_seconds = params[:timeout_seconds] || 60
          @variables = params[:variables] || {}
          @input_template = params[:input_template] || {}
        end
      end
    end
  end
end
