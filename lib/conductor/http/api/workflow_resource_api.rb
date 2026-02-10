# frozen_string_literal: true

require_relative '../api_client'

module Conductor
  module Http
    module Api
      # WorkflowResourceApi - API for workflow operations
      class WorkflowResourceApi
        attr_accessor :api_client

        # Initialize WorkflowResourceApi
        # @param [ApiClient] api_client Optional API client
        def initialize(api_client = nil)
          @api_client = api_client || ApiClient.new
        end

        # Start a workflow execution
        # @param [StartWorkflowRequest] body Start workflow request
        # @return [String] Workflow ID
        def start_workflow(body)
          @api_client.call_api(
            '/workflow',
            'POST',
            body: body,
            return_type: 'String',
            return_http_data_only: true
          )
        end

        # Get workflow execution status
        # @param [String] workflow_id Workflow ID
        # @param [Boolean] include_tasks Include task details (default: true)
        # @return [Workflow] Workflow object
        def get_execution_status(workflow_id, include_tasks: true)
          @api_client.call_api(
            '/workflow/{workflowId}',
            'GET',
            path_params: { workflowId: workflow_id },
            query_params: { includeTasks: include_tasks },
            return_type: 'Workflow',
            return_http_data_only: true
          )
        end

        # Delete a workflow
        # @param [String] workflow_id Workflow ID
        # @param [Boolean] archive_workflow Archive workflow before deleting (default: true)
        # @return [void]
        def delete(workflow_id, archive_workflow: true)
          @api_client.call_api(
            '/workflow/{workflowId}/remove',
            'DELETE',
            path_params: { workflowId: workflow_id },
            query_params: { archiveWorkflow: archive_workflow },
            return_http_data_only: true
          )
        end

        # Pause a workflow
        # @param [String] workflow_id Workflow ID
        # @return [void]
        def pause_workflow(workflow_id)
          @api_client.call_api(
            '/workflow/{workflowId}/pause',
            'PUT',
            path_params: { workflowId: workflow_id },
            return_http_data_only: true
          )
        end

        # Resume a paused workflow
        # @param [String] workflow_id Workflow ID
        # @return [void]
        def resume_workflow(workflow_id)
          @api_client.call_api(
            '/workflow/{workflowId}/resume',
            'PUT',
            path_params: { workflowId: workflow_id },
            return_http_data_only: true
          )
        end

        # Restart a completed workflow
        # @param [String] workflow_id Workflow ID
        # @param [Boolean] use_latest_def Use latest workflow definition (default: false)
        # @return [void]
        def restart(workflow_id, use_latest_def: false)
          @api_client.call_api(
            '/workflow/{workflowId}/restart',
            'POST',
            path_params: { workflowId: workflow_id },
            query_params: { useLatestDefinitions: use_latest_def },
            return_http_data_only: true
          )
        end

        # Rerun a workflow from a specific task
        # @param [String] workflow_id Workflow ID
        # @param [RerunWorkflowRequest] body Rerun request
        # @return [String] New workflow ID
        def rerun(workflow_id, body)
          @api_client.call_api(
            '/workflow/{workflowId}/rerun',
            'POST',
            path_params: { workflowId: workflow_id },
            body: body,
            return_type: 'String',
            return_http_data_only: true
          )
        end

        # Terminate a running workflow
        # @param [String] workflow_id Workflow ID
        # @param [String] reason Termination reason
        # @return [void]
        def terminate(workflow_id, reason: nil)
          @api_client.call_api(
            '/workflow/{workflowId}',
            'DELETE',
            path_params: { workflowId: workflow_id },
            query_params: reason ? { reason: reason } : {},
            return_http_data_only: true
          )
        end

        # Retry a failed workflow
        # @param [String] workflow_id Workflow ID
        # @param [Boolean] resume_subworkflow_tasks Resume subworkflow tasks (default: false)
        # @return [void]
        def retry(workflow_id, resume_subworkflow_tasks: false)
          @api_client.call_api(
            '/workflow/{workflowId}/retry',
            'POST',
            path_params: { workflowId: workflow_id },
            query_params: { resumeSubworkflowTasks: resume_subworkflow_tasks },
            return_http_data_only: true
          )
        end

        # Get workflows by correlation ID
        # @param [String] name Workflow name
        # @param [String] correlation_id Correlation ID
        # @param [Boolean] include_closed Include closed workflows (default: false)
        # @param [Boolean] include_tasks Include task details (default: false)
        # @return [Array<Workflow>] List of workflows
        def get_workflows(name, correlation_id, include_closed: false, include_tasks: false)
          @api_client.call_api(
            '/workflow/{name}/correlated/{correlationId}',
            'GET',
            path_params: { name: name, correlationId: correlation_id },
            query_params: { includeClosed: include_closed, includeTasks: include_tasks },
            return_type: 'Array<Workflow>',
            return_http_data_only: true
          )
        end

        # Get running workflows by name
        # @param [String] name Workflow name
        # @param [Integer] version Workflow version (optional)
        # @param [Integer] start_time Start time (epoch millis, optional)
        # @param [Integer] end_time End time (epoch millis, optional)
        # @return [Array<String>] List of workflow IDs
        def get_running_workflow(name, version: nil, start_time: nil, end_time: nil)
          query_params = {}
          query_params[:version] = version if version
          query_params[:startTime] = start_time if start_time
          query_params[:endTime] = end_time if end_time

          @api_client.call_api(
            '/workflow/running/{name}',
            'GET',
            path_params: { name: name },
            query_params: query_params,
            return_type: 'Array<String>',
            return_http_data_only: true
          )
        end

        # Register a workflow definition
        # @param [WorkflowDef] body Workflow definition
        # @param [Boolean] overwrite Overwrite existing definition (default: false)
        # @return [void]
        def register_workflow(body, overwrite: false)
          @api_client.call_api(
            '/metadata/workflow',
            'POST',
            query_params: { overwrite: overwrite },
            body: body,
            return_http_data_only: true
          )
        end

        # Get a workflow definition
        # @param [String] name Workflow name
        # @param [Integer] version Workflow version (optional)
        # @return [WorkflowDef] Workflow definition
        def get_workflow_def(name, version: nil)
          query_params = {}
          query_params[:version] = version if version

          @api_client.call_api(
            '/metadata/workflow/{name}',
            'GET',
            path_params: { name: name },
            query_params: query_params,
            return_type: 'WorkflowDef',
            return_http_data_only: true
          )
        end

        # Delete a workflow definition
        # @param [String] name Workflow name
        # @param [Integer] version Workflow version
        # @return [void]
        def unregister_workflow(name, version:)
          @api_client.call_api(
            '/metadata/workflow/{name}/{version}',
            'DELETE',
            path_params: { name: name, version: version },
            return_http_data_only: true
          )
        end

        # Execute a workflow synchronously and wait for completion
        # @param [StartWorkflowRequest] body Start workflow request
        # @param [String] name Workflow name
        # @param [Integer] version Workflow version
        # @param [String] request_id Unique request ID for idempotency
        # @param [String] wait_until_task_ref Wait until this task completes (optional)
        # @param [Integer] wait_for_seconds Maximum time to wait (default: 10)
        # @return [WorkflowRun] Workflow run result
        def execute_workflow(body, name:, version:, request_id:, wait_until_task_ref: nil, wait_for_seconds: 10)
          query_params = {
            requestId: request_id,
            waitForSeconds: wait_for_seconds
          }
          query_params[:waitUntilTaskRef] = wait_until_task_ref if wait_until_task_ref

          @api_client.call_api(
            '/workflow/execute/{name}/{version}',
            'POST',
            path_params: { name: name, version: version },
            query_params: query_params,
            body: body,
            return_type: 'WorkflowRun',
            return_http_data_only: true
          )
        end

        # Get workflow status (lightweight, without full task details)
        # @param [String] workflow_id Workflow ID
        # @param [Boolean] include_output Include workflow output (default: false)
        # @param [Boolean] include_variables Include workflow variables (default: false)
        # @return [Hash] Workflow status
        def get_workflow_status(workflow_id, include_output: false, include_variables: false)
          @api_client.call_api(
            '/workflow/{workflowId}/status',
            'GET',
            path_params: { workflowId: workflow_id },
            query_params: { includeOutput: include_output, includeVariables: include_variables },
            return_type: 'Hash',
            return_http_data_only: true
          )
        end

        # Skip a task in a running workflow
        # @param [String] workflow_id Workflow ID
        # @param [String] task_reference_name Task reference name to skip
        # @param [Hash] request Skip task request body (optional)
        # @return [void]
        def skip_task_from_workflow(workflow_id, task_reference_name, request: nil)
          @api_client.call_api(
            '/workflow/{workflowId}/skiptask/{taskReferenceName}',
            'PUT',
            path_params: { workflowId: workflow_id, taskReferenceName: task_reference_name },
            body: request,
            return_http_data_only: true
          )
        end

        # Decide on workflow (evaluate next steps)
        # @param [String] workflow_id Workflow ID
        # @return [void]
        def decide(workflow_id)
          @api_client.call_api(
            '/workflow/decide/{workflowId}',
            'PUT',
            path_params: { workflowId: workflow_id },
            return_http_data_only: true
          )
        end

        # Reset workflow callbacks
        # @param [String] workflow_id Workflow ID
        # @return [void]
        def reset_workflow(workflow_id)
          @api_client.call_api(
            '/workflow/{workflowId}/resetcallbacks',
            'POST',
            path_params: { workflowId: workflow_id },
            return_http_data_only: true
          )
        end

        # Search for workflows
        # @param [Integer] start Start index (default: 0)
        # @param [Integer] size Page size (default: 100)
        # @param [String] free_text Free text search (default: '*')
        # @param [String] query Query string (optional)
        # @param [Boolean] skip_cache Skip cache (default: false)
        # @return [SearchResult] Search results with workflow summaries
        def search(start: 0, size: 100, free_text: '*', query: nil, skip_cache: false)
          query_params = { start: start, size: size, freeText: free_text, skipCache: skip_cache }
          query_params[:query] = query if query

          @api_client.call_api(
            '/workflow/search',
            'GET',
            query_params: query_params,
            return_type: 'SearchResult',
            return_http_data_only: true
          )
        end

        # Update workflow variables
        # @param [String] workflow_id Workflow ID
        # @param [Hash] variables Variables to update
        # @return [Workflow]
        def update_workflow_state(workflow_id, variables)
          @api_client.call_api(
            '/workflow/{workflowId}/variables',
            'POST',
            path_params: { workflowId: workflow_id },
            body: variables,
            return_type: 'Workflow',
            return_http_data_only: true
          )
        end

        # Update workflow and task state
        # @param [String] workflow_id Workflow ID
        # @param [WorkflowStateUpdate] body State update request
        # @param [String] request_id Request ID (optional)
        # @param [String] wait_until_task_ref Wait until task ref (optional)
        # @param [Integer] wait_for_seconds Wait time in seconds (default: 10)
        # @return [WorkflowRun]
        def update_workflow_and_task_state(workflow_id, body, request_id: nil, wait_until_task_ref: nil, wait_for_seconds: 10)
          query_params = { waitForSeconds: wait_for_seconds }
          query_params[:requestId] = request_id if request_id
          query_params[:waitUntilTaskRef] = wait_until_task_ref if wait_until_task_ref

          @api_client.call_api(
            '/workflow/{workflowId}/state',
            'POST',
            path_params: { workflowId: workflow_id },
            query_params: query_params,
            body: body,
            return_type: 'WorkflowRun',
            return_http_data_only: true
          )
        end

        # Test a workflow with mocked task outputs
        # @param [WorkflowTestRequest] body Test request
        # @return [Workflow]
        def test_workflow(body)
          @api_client.call_api(
            '/workflow/test',
            'POST',
            body: body,
            return_type: 'Workflow',
            return_http_data_only: true
          )
        end

        # Get workflows by multiple correlation IDs (batch)
        # @param [String] name Workflow name
        # @param [Array<String>] correlation_ids List of correlation IDs
        # @param [Boolean] include_closed Include closed workflows (default: false)
        # @param [Boolean] include_tasks Include task details (default: false)
        # @return [Hash<String, Array<Workflow>>]
        def get_workflows_batch(name, correlation_ids, include_closed: false, include_tasks: false)
          @api_client.call_api(
            '/workflow/{name}/correlated',
            'POST',
            path_params: { name: name },
            query_params: { includeClosed: include_closed, includeTasks: include_tasks },
            body: correlation_ids,
            return_type: 'Hash<String, Object>',
            return_http_data_only: true
          )
        end

        # Start a workflow by name (alternative endpoint)
        # @param [String] name Workflow name
        # @param [Hash] body Workflow input
        # @param [Integer] version Workflow version (optional)
        # @param [String] correlation_id Correlation ID (optional)
        # @param [Integer] priority Priority (optional)
        # @return [String] Workflow ID
        def start_workflow_by_name(name, body, version: nil, correlation_id: nil, priority: nil)
          query_params = {}
          query_params[:version] = version if version
          query_params[:correlationId] = correlation_id if correlation_id
          query_params[:priority] = priority if priority

          @api_client.call_api(
            '/workflow/{name}',
            'POST',
            path_params: { name: name },
            query_params: query_params,
            body: body,
            return_type: 'String',
            return_http_data_only: true
          )
        end

        # Jump to a specific task in a workflow
        # @param [String] workflow_id Workflow ID
        # @param [String] task_reference_name Task reference name
        # @param [Hash] input Task input (optional)
        # @return [void]
        def jump_to_task(workflow_id, task_reference_name, input: nil)
          @api_client.call_api(
            '/workflow/{workflowId}/jump/{taskReferenceName}',
            'POST',
            path_params: { workflowId: workflow_id, taskReferenceName: task_reference_name },
            body: input,
            return_http_data_only: true
          )
        end

        # Upgrade a running workflow to a new version
        # @param [String] workflow_id Workflow ID
        # @param [Hash] body Upgrade request
        # @return [void]
        def upgrade_running_workflow(workflow_id, body)
          @api_client.call_api(
            '/workflow/{workflowId}/upgrade',
            'POST',
            path_params: { workflowId: workflow_id },
            body: body,
            return_http_data_only: true
          )
        end
      end
    end
  end
end
