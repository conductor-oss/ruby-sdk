# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # Workflow execution model representing a running or completed workflow instance
      class Workflow < BaseModel
        SWAGGER_TYPES = {
          workflow_id: 'String',
          parent_workflow_id: 'String',
          parent_workflow_task_id: 'String',
          correlation_id: 'String',
          workflow_name: 'String',
          workflow_version: 'Integer',
          workflow_definition: 'WorkflowDef',
          status: 'String',
          input: 'Hash<String, Object>',
          output: 'Hash<String, Object>',
          tasks: 'Array<Task>',
          start_time: 'Integer',
          end_time: 'Integer',
          update_time: 'Integer',
          variables: 'Hash<String, Object>',
          external_input_payload_storage_path: 'String',
          external_output_payload_storage_path: 'String',
          priority: 'Integer',
          task_to_domain: 'Hash<String, String>',
          failed_reference_task_names: 'Array<String>',
          reason_for_incompletion: 'String',
          owner_app: 'String',
          created_by: 'String',
          event: 'String',
          last_retried_time: 'Integer'
        }.freeze

        ATTRIBUTE_MAP = {
          workflow_id: :workflowId,
          parent_workflow_id: :parentWorkflowId,
          parent_workflow_task_id: :parentWorkflowTaskId,
          correlation_id: :correlationId,
          workflow_name: :workflowName,
          workflow_version: :workflowVersion,
          workflow_definition: :workflowDefinition,
          status: :status,
          input: :input,
          output: :output,
          tasks: :tasks,
          start_time: :startTime,
          end_time: :endTime,
          update_time: :updateTime,
          variables: :variables,
          external_input_payload_storage_path: :externalInputPayloadStoragePath,
          external_output_payload_storage_path: :externalOutputPayloadStoragePath,
          priority: :priority,
          task_to_domain: :taskToDomain,
          failed_reference_task_names: :failedReferenceTaskNames,
          reason_for_incompletion: :reasonForIncompletion,
          owner_app: :ownerApp,
          created_by: :createdBy,
          event: :event,
          last_retried_time: :lastRetriedTime
        }.freeze

        attr_accessor :workflow_id, :parent_workflow_id, :parent_workflow_task_id,
                      :correlation_id, :workflow_name, :workflow_version,
                      :workflow_definition, :status, :input, :output, :tasks,
                      :start_time, :end_time, :update_time, :variables,
                      :external_input_payload_storage_path,
                      :external_output_payload_storage_path, :priority,
                      :task_to_domain, :failed_reference_task_names,
                      :reason_for_incompletion, :owner_app, :created_by,
                      :event, :last_retried_time

        def initialize(params = {})
          @workflow_id = params[:workflow_id]
          @parent_workflow_id = params[:parent_workflow_id]
          @parent_workflow_task_id = params[:parent_workflow_task_id]
          @correlation_id = params[:correlation_id]
          @workflow_name = params[:workflow_name]
          @workflow_version = params[:workflow_version]
          @workflow_definition = params[:workflow_definition]
          @status = params[:status]
          @input = params[:input] || {}
          @output = params[:output] || {}
          @tasks = params[:tasks] || []
          @start_time = params[:start_time]
          @end_time = params[:end_time]
          @update_time = params[:update_time]
          @variables = params[:variables] || {}
          @external_input_payload_storage_path = params[:external_input_payload_storage_path]
          @external_output_payload_storage_path = params[:external_output_payload_storage_path]
          @priority = params[:priority]
          @task_to_domain = params[:task_to_domain]
          @failed_reference_task_names = params[:failed_reference_task_names] || []
          @reason_for_incompletion = params[:reason_for_incompletion]
          @owner_app = params[:owner_app]
          @created_by = params[:created_by]
          @event = params[:event]
          @last_retried_time = params[:last_retried_time]
        end

        # Check if workflow is in terminal state
        # @return [Boolean]
        def terminal?
          WorkflowStatusConstants.terminal?(status)
        end

        # Check if workflow completed successfully
        # @return [Boolean]
        def completed?
          status == WorkflowStatusConstants::COMPLETED
        end

        # Check if workflow failed
        # @return [Boolean]
        def failed?
          status == WorkflowStatusConstants::FAILED
        end

        # Check if workflow is running
        # @return [Boolean]
        def running?
          status == WorkflowStatusConstants::RUNNING
        end

        # Check if workflow is paused
        # @return [Boolean]
        def paused?
          status == WorkflowStatusConstants::PAUSED
        end

        # Get a task by reference name
        # @param ref_name [String] Task reference name
        # @return [Task, nil]
        def task_by_ref(ref_name)
          tasks&.find { |t| t.reference_task_name == ref_name }
        end
      end

      # WorkflowRun represents the result of executing a workflow synchronously
      class WorkflowRun < BaseModel
        SWAGGER_TYPES = {
          workflow_id: 'String',
          correlation_id: 'String',
          status: 'String',
          input: 'Hash<String, Object>',
          output: 'Hash<String, Object>',
          tasks: 'Array<Task>',
          request_id: 'String',
          created_by: 'String',
          variables: 'Hash<String, Object>',
          priority: 'Integer',
          reason_for_incompletion: 'String'
        }.freeze

        ATTRIBUTE_MAP = {
          workflow_id: :workflowId,
          correlation_id: :correlationId,
          status: :status,
          input: :input,
          output: :output,
          tasks: :tasks,
          request_id: :requestId,
          created_by: :createdBy,
          variables: :variables,
          priority: :priority,
          reason_for_incompletion: :reasonForIncompletion
        }.freeze

        attr_accessor :workflow_id, :correlation_id, :status, :input, :output,
                      :tasks, :request_id, :created_by, :variables, :priority,
                      :reason_for_incompletion

        def initialize(params = {})
          @workflow_id = params[:workflow_id]
          @correlation_id = params[:correlation_id]
          @status = params[:status]
          @input = params[:input] || {}
          @output = params[:output] || {}
          @tasks = params[:tasks] || []
          @request_id = params[:request_id]
          @created_by = params[:created_by]
          @variables = params[:variables] || {}
          @priority = params[:priority]
          @reason_for_incompletion = params[:reason_for_incompletion]
        end

        # Check if workflow completed successfully
        # @return [Boolean]
        def completed?
          status == WorkflowStatusConstants::COMPLETED
        end

        # Check if workflow is still running
        # @return [Boolean]
        def running?
          status == WorkflowStatusConstants::RUNNING
        end
      end
    end
  end
end
