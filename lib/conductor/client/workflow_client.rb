# frozen_string_literal: true

require 'securerandom'
require_relative '../configuration'
require_relative '../http/api_client'
require_relative '../http/api/workflow_resource_api'

module Conductor
  module Client
    # WorkflowClient - High-level client for workflow operations
    class WorkflowClient
      attr_reader :workflow_api

      # Initialize WorkflowClient
      # @param [Configuration] configuration Optional configuration
      def initialize(configuration = nil)
        @configuration = configuration || Configuration.new
        api_client = Http::ApiClient.new(configuration: @configuration)
        @workflow_api = Http::Api::WorkflowResourceApi.new(api_client)
      end

      # Start a new workflow
      # @param [StartWorkflowRequest] request Start workflow request
      # @return [String] Workflow ID
      def start_workflow(request)
        @workflow_api.start_workflow(request)
      end

      # Start a workflow with name and input, or with a StartWorkflowRequest
      # @param [String, StartWorkflowRequest] name_or_request Workflow name or StartWorkflowRequest
      # @param [Hash] input Workflow input data (default: {}, ignored if request object passed)
      # @param [Integer] version Workflow version (optional, ignored if request object passed)
      # @param [String] correlation_id Correlation ID (optional, ignored if request object passed)
      # @return [String] Workflow ID
      def start(name_or_request, input: {}, version: nil, correlation_id: nil)
        # Handle both StartWorkflowRequest objects and simple name/input arguments
        if name_or_request.is_a?(Http::Models::StartWorkflowRequest)
          start_workflow(name_or_request)
        else
          request = Http::Models::StartWorkflowRequest.new(
            name: name_or_request,
            input: input,
            version: version,
            correlation_id: correlation_id
          )
          start_workflow(request)
        end
      end

      # Get workflow execution status
      # @param [String] workflow_id Workflow ID
      # @param [Boolean] include_tasks Include task details (default: true)
      # @return [Workflow] Workflow object
      def get_workflow(workflow_id, include_tasks: true)
        @workflow_api.get_execution_status(workflow_id, include_tasks: include_tasks)
      end

      # Delete a workflow
      # @param [String] workflow_id Workflow ID
      # @param [Boolean] archive_workflow Archive workflow before deleting (default: true)
      # @return [void]
      def delete_workflow(workflow_id, archive_workflow: true)
        @workflow_api.delete(workflow_id, archive_workflow: archive_workflow)
      end

      # Terminate a running workflow
      # @param [String] workflow_id Workflow ID
      # @param [String] reason Termination reason (optional)
      # @return [void]
      def terminate_workflow(workflow_id, reason: nil)
        @workflow_api.terminate(workflow_id, reason: reason)
      end

      # Pause a workflow
      # @param [String] workflow_id Workflow ID
      # @return [void]
      def pause_workflow(workflow_id)
        @workflow_api.pause_workflow(workflow_id)
      end

      # Resume a paused workflow
      # @param [String] workflow_id Workflow ID
      # @return [void]
      def resume_workflow(workflow_id)
        @workflow_api.resume_workflow(workflow_id)
      end

      # Restart a completed workflow
      # @param [String] workflow_id Workflow ID
      # @param [Boolean] use_latest_def Use latest workflow definition (default: false)
      # @return [void]
      def restart_workflow(workflow_id, use_latest_def: false)
        @workflow_api.restart(workflow_id, use_latest_def: use_latest_def)
      end

      # Retry a failed workflow
      # @param [String] workflow_id Workflow ID
      # @param [Boolean] resume_subworkflow_tasks Resume subworkflow tasks (default: false)
      # @return [void]
      def retry_workflow(workflow_id, resume_subworkflow_tasks: false)
        @workflow_api.retry(workflow_id, resume_subworkflow_tasks: resume_subworkflow_tasks)
      end

      # Rerun a workflow from a specific task
      # @param [String] workflow_id Workflow ID
      # @param [RerunWorkflowRequest] rerun_request Rerun request
      # @return [String] New workflow ID
      def rerun_workflow(workflow_id, rerun_request)
        @workflow_api.rerun(workflow_id, rerun_request)
      end

      # Get workflows by correlation ID
      # @param [String] name Workflow name
      # @param [String] correlation_id Correlation ID
      # @param [Boolean] include_closed Include closed workflows (default: false)
      # @param [Boolean] include_tasks Include task details (default: false)
      # @return [Array<Workflow>] List of workflows
      def get_by_correlation_id(name, correlation_id, include_closed: false, include_tasks: false)
        @workflow_api.get_workflows(name, correlation_id, include_closed: include_closed, include_tasks: include_tasks)
      end

      # Get running workflows by name
      # @param [String] name Workflow name
      # @param [Integer] version Workflow version (optional)
      # @param [Integer] start_time Start time in epoch millis (optional)
      # @param [Integer] end_time End time in epoch millis (optional)
      # @return [Array<String>] List of workflow IDs
      def get_running_workflows(name, version: nil, start_time: nil, end_time: nil)
        @workflow_api.get_running_workflow(name, version: version, start_time: start_time, end_time: end_time)
      end

      # Register a workflow definition
      # @param [WorkflowDef] workflow_def Workflow definition to register
      # @param [Boolean] overwrite Overwrite existing definition (default: false)
      # @return [void]
      def register_workflow(workflow_def, overwrite: false)
        @workflow_api.register_workflow(workflow_def, overwrite: overwrite)
      end

      # Get a workflow definition
      # @param [String] name Workflow name
      # @param [Integer] version Workflow version (optional)
      # @return [WorkflowDef] Workflow definition
      def get_workflow_def(name, version: nil)
        @workflow_api.get_workflow_def(name, version: version)
      end

      # Delete a workflow definition
      # @param [String] name Workflow name
      # @param [Integer] version Workflow version
      # @return [void]
      def unregister_workflow(name, version:)
        @workflow_api.unregister_workflow(name, version: version)
      end

      # Execute a workflow synchronously and wait for completion
      # @param [StartWorkflowRequest] request Start workflow request
      # @param [String] request_id Unique request ID (optional, auto-generated)
      # @param [String] wait_until_task_ref Wait until task ref (optional)
      # @param [Integer] wait_for_seconds Max wait time (default: 30)
      # @return [WorkflowRun] Workflow run result
      def execute_workflow(request, request_id: nil, wait_until_task_ref: nil, wait_for_seconds: 30)
        request_id ||= SecureRandom.uuid
        @workflow_api.execute_workflow(
          request,
          name: request.name,
          version: request.version || 1,
          request_id: request_id,
          wait_until_task_ref: wait_until_task_ref,
          wait_for_seconds: wait_for_seconds
        )
      end

      # Search for workflows
      # @param [Integer] start Start index (default: 0)
      # @param [Integer] size Page size (default: 100)
      # @param [String] free_text Free text search (default: '*')
      # @param [String] query Query string (optional)
      # @return [SearchResult] Search results
      def search(start: 0, size: 100, free_text: '*', query: nil)
        @workflow_api.search(start: start, size: size, free_text: free_text, query: query)
      end

      # Get workflows by multiple correlation IDs (batch)
      # @param [String] name Workflow name
      # @param [Array<String>] correlation_ids Correlation IDs
      # @param [Boolean] include_closed Include closed workflows (default: false)
      # @param [Boolean] include_tasks Include task details (default: false)
      # @return [Hash<String, Array<Workflow>>]
      def get_by_correlation_ids(name, correlation_ids, include_closed: false, include_tasks: false)
        @workflow_api.get_workflows_batch(name, correlation_ids, include_closed: include_closed,
                                                                 include_tasks: include_tasks)
      end

      # Update workflow variables
      # @param [String] workflow_id Workflow ID
      # @param [Hash] variables Variables to update
      # @return [Workflow]
      def update_variables(workflow_id, variables)
        @workflow_api.update_workflow_state(workflow_id, variables)
      end

      # Update workflow and task state
      # @param [String] workflow_id Workflow ID
      # @param [WorkflowStateUpdate] state_update State update request
      # @param [String] wait_until_task_ref Wait until task ref (optional)
      # @param [Integer] wait_for_seconds Wait time (default: 10)
      # @return [WorkflowRun]
      def update_state(workflow_id, state_update, wait_until_task_ref: nil, wait_for_seconds: 10)
        @workflow_api.update_workflow_and_task_state(
          workflow_id, state_update,
          wait_until_task_ref: wait_until_task_ref,
          wait_for_seconds: wait_for_seconds
        )
      end

      # Test a workflow with mocked task outputs
      # @param [WorkflowTestRequest] request Test request
      # @return [Workflow]
      def test_workflow(request)
        @workflow_api.test_workflow(request)
      end

      # Skip a task in a running workflow
      # @param [String] workflow_id Workflow ID
      # @param [String] task_reference_name Task reference name
      # @param [SkipTaskRequest] request Skip task request (optional)
      # @return [void]
      def skip_task_from_workflow(workflow_id, task_reference_name, request: nil)
        @workflow_api.skip_task_from_workflow(workflow_id, task_reference_name, request: request)
      end

      # Remove (permanently delete) a workflow
      # @param [String] workflow_id Workflow ID
      # @param [Boolean] archive_workflow Archive before deleting (default: true)
      # @return [void]
      def remove_workflow(workflow_id, archive_workflow: true)
        @workflow_api.delete(workflow_id, archive_workflow: archive_workflow)
      end
    end
  end
end
