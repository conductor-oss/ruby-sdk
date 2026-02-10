# frozen_string_literal: true

require 'securerandom'
require_relative '../configuration'
require_relative '../http/api_client'
require_relative '../http/api/workflow_resource_api'
require_relative '../http/api/metadata_resource_api'
require_relative '../http/api/task_resource_api'
require_relative '../http/models/start_workflow_request'

module Conductor
  module Workflow
    # WorkflowExecutor provides a high-level interface for executing workflows
    # Supports both synchronous (wait for completion) and asynchronous execution
    class WorkflowExecutor
      attr_reader :workflow_api, :metadata_api, :task_api

      # Initialize WorkflowExecutor
      # @param [Configuration] configuration Optional configuration
      def initialize(configuration = nil)
        @configuration = configuration || Configuration.new
        api_client = Http::ApiClient.new(configuration: @configuration)
        @workflow_api = Http::Api::WorkflowResourceApi.new(api_client)
        @metadata_api = Http::Api::MetadataResourceApi.new(api_client)
        @task_api = Http::Api::TaskResourceApi.new(api_client)
      end

      # ==========================================
      # Workflow Definition Operations
      # ==========================================

      # Register a workflow definition
      # @param [WorkflowDef, ConductorWorkflow] workflow Workflow definition or ConductorWorkflow DSL
      # @param [Boolean] overwrite Overwrite existing definition (default: true)
      # @return [Object] Response
      def register_workflow(workflow, overwrite: true)
        workflow_def = workflow.respond_to?(:to_workflow_def) ? workflow.to_workflow_def : workflow
        @metadata_api.update_workflows([workflow_def], overwrite: overwrite)
      end

      # ==========================================
      # Workflow Execution Operations
      # ==========================================

      # Start a workflow asynchronously (returns immediately with workflow ID)
      # @param [StartWorkflowRequest] request Start workflow request
      # @return [String] Workflow ID
      def start_workflow(request)
        @workflow_api.start_workflow(request)
      end

      # Start multiple workflows
      # @param [Array<StartWorkflowRequest>] requests List of start workflow requests
      # @return [Array<String>] List of workflow IDs
      def start_workflows(*requests)
        requests.flatten.map { |request| start_workflow(request) }
      end

      # Execute a workflow synchronously and wait for completion
      # @param [StartWorkflowRequest] request Start workflow request
      # @param [String] wait_until_task_ref Wait until this task completes (optional)
      # @param [Integer] wait_for_seconds Maximum time to wait (default: 10)
      # @param [String] request_id Unique request ID for idempotency (auto-generated if not provided)
      # @return [WorkflowRun] Workflow run result
      def execute_workflow(request, wait_until_task_ref: nil, wait_for_seconds: 10, request_id: nil)
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

      # Execute a workflow by name with input (convenience method)
      # @param [String] name Workflow name
      # @param [Hash] input Workflow input (default: {})
      # @param [Integer] version Workflow version (optional)
      # @param [String] correlation_id Correlation ID (optional)
      # @param [String] domain Task domain for all tasks (optional)
      # @param [String] wait_until_task_ref Wait until this task completes (optional)
      # @param [Integer] wait_for_seconds Maximum time to wait (default: 10)
      # @param [String] request_id Unique request ID (optional)
      # @return [WorkflowRun] Workflow run result
      def execute(name, input: {}, version: nil, correlation_id: nil, domain: nil,
                  wait_until_task_ref: nil, wait_for_seconds: 10, request_id: nil)
        request = Http::Models::StartWorkflowRequest.new(
          name: name,
          input: input,
          version: version,
          correlation_id: correlation_id
        )
        request.task_to_domain = { '*' => domain } if domain

        execute_workflow(
          request,
          wait_until_task_ref: wait_until_task_ref,
          wait_for_seconds: wait_for_seconds,
          request_id: request_id
        )
      end

      # ==========================================
      # Workflow Status Operations
      # ==========================================

      # Get workflow execution details
      # @param [String] workflow_id Workflow ID
      # @param [Boolean] include_tasks Include task details (default: true)
      # @return [Workflow] Workflow object
      def get_workflow(workflow_id, include_tasks: true)
        @workflow_api.get_execution_status(workflow_id, include_tasks: include_tasks)
      end

      # Get workflow status (lightweight)
      # @param [String] workflow_id Workflow ID
      # @param [Boolean] include_output Include workflow output (default: false)
      # @param [Boolean] include_variables Include workflow variables (default: false)
      # @return [Hash] Workflow status
      def get_workflow_status(workflow_id, include_output: false, include_variables: false)
        @workflow_api.get_workflow_status(
          workflow_id,
          include_output: include_output,
          include_variables: include_variables
        )
      end

      # ==========================================
      # Workflow Control Operations
      # ==========================================

      # Pause a running workflow
      # @param [String] workflow_id Workflow ID
      # @return [void]
      def pause(workflow_id)
        @workflow_api.pause_workflow(workflow_id)
      end

      # Resume a paused workflow
      # @param [String] workflow_id Workflow ID
      # @return [void]
      def resume(workflow_id)
        @workflow_api.resume_workflow(workflow_id)
      end

      # Terminate a running workflow
      # @param [String] workflow_id Workflow ID
      # @param [String] reason Termination reason (optional)
      # @return [void]
      def terminate(workflow_id, reason: nil)
        @workflow_api.terminate(workflow_id, reason: reason)
      end

      # Restart a completed workflow
      # @param [String] workflow_id Workflow ID
      # @param [Boolean] use_latest_definitions Use latest workflow definition (default: false)
      # @return [void]
      def restart(workflow_id, use_latest_definitions: false)
        @workflow_api.restart(workflow_id, use_latest_def: use_latest_definitions)
      end

      # Retry a failed workflow
      # @param [String] workflow_id Workflow ID
      # @param [Boolean] resume_subworkflow_tasks Resume subworkflow tasks (default: false)
      # @return [void]
      def retry(workflow_id, resume_subworkflow_tasks: false)
        @workflow_api.retry(workflow_id, resume_subworkflow_tasks: resume_subworkflow_tasks)
      end

      # Rerun a workflow from a specific task
      # @param [String] workflow_id Workflow ID
      # @param [Hash, RerunWorkflowRequest] rerun_request Rerun configuration
      # @return [String] New workflow ID
      def rerun(workflow_id, rerun_request)
        @workflow_api.rerun(workflow_id, rerun_request)
      end

      # Remove (delete) a workflow permanently
      # @param [String] workflow_id Workflow ID
      # @param [Boolean] archive_workflow Archive before deleting (default: true)
      # @return [void]
      def remove_workflow(workflow_id, archive_workflow: true)
        @workflow_api.delete(workflow_id, archive_workflow: archive_workflow)
      end

      # Skip a task in a running workflow
      # @param [String] workflow_id Workflow ID
      # @param [String] task_reference_name Task reference name to skip
      # @param [Hash] request Skip task request (optional)
      # @return [void]
      def skip_task_from_workflow(workflow_id, task_reference_name, request: nil)
        @workflow_api.skip_task_from_workflow(workflow_id, task_reference_name, request: request)
      end

      # ==========================================
      # Task Operations
      # ==========================================

      # Update a task result
      # @param [String] workflow_id Workflow ID
      # @param [String] task_id Task ID
      # @param [Hash] task_output Task output data
      # @param [String] status Task status (COMPLETED, FAILED, etc.)
      # @return [String] Task update result
      def update_task(workflow_id, task_id, task_output, status)
        task_result = Http::Models::TaskResult.new(
          workflow_instance_id: workflow_id,
          task_id: task_id,
          output_data: task_output,
          status: status
        )
        @task_api.update_task(task_result)
      end

      # Update a task by reference name
      # @param [String] workflow_id Workflow ID
      # @param [String] task_reference_name Task reference name
      # @param [Hash] task_output Task output data
      # @param [String] status Task status
      # @return [String] Task update result
      def update_task_by_ref_name(workflow_id, task_reference_name, task_output, status)
        @task_api.update_task_by_ref_name(
          task_output,
          workflow_id: workflow_id,
          task_ref_name: task_reference_name,
          status: status
        )
      end

      # Get a task by ID
      # @param [String] task_id Task ID
      # @return [Task] Task object
      def get_task(task_id)
        @task_api.get_task(task_id)
      end

      # ==========================================
      # Correlation ID Operations
      # ==========================================

      # Get workflows by correlation ID
      # @param [String] workflow_name Workflow name
      # @param [String] correlation_id Correlation ID
      # @param [Boolean] include_closed Include closed workflows (default: false)
      # @param [Boolean] include_tasks Include task details (default: false)
      # @return [Array<Workflow>] List of workflows
      def get_by_correlation_id(workflow_name, correlation_id, include_closed: false, include_tasks: false)
        @workflow_api.get_workflows(
          workflow_name,
          correlation_id,
          include_closed: include_closed,
          include_tasks: include_tasks
        )
      end

      # Get workflows by multiple correlation IDs
      # @param [String] workflow_name Workflow name
      # @param [Array<String>] correlation_ids List of correlation IDs
      # @param [Boolean] include_closed Include closed workflows (default: false)
      # @param [Boolean] include_tasks Include task details (default: false)
      # @return [Hash<String, Array<Workflow>>] Map of correlation ID to workflows
      def get_by_correlation_ids(workflow_name, correlation_ids, include_closed: false, include_tasks: false)
        # NOTE: This would require a batch API endpoint; for now, iterate
        result = {}
        correlation_ids.each do |correlation_id|
          result[correlation_id] = get_by_correlation_id(
            workflow_name,
            correlation_id,
            include_closed: include_closed,
            include_tasks: include_tasks
          )
        end
        result
      end

      # ==========================================
      # Polling Helpers
      # ==========================================

      # Wait for a workflow to complete
      # @param [String] workflow_id Workflow ID
      # @param [Integer] timeout_seconds Maximum time to wait (default: 60)
      # @param [Float] poll_interval_seconds Polling interval (default: 1.0)
      # @return [Workflow] Completed workflow
      # @raise [Timeout::Error] If workflow doesn't complete within timeout
      def wait_for_workflow(workflow_id, timeout_seconds: 60, poll_interval_seconds: 1.0)
        deadline = Time.now + timeout_seconds

        loop do
          workflow = get_workflow(workflow_id, include_tasks: false)
          return workflow if workflow.terminal?

          raise Timeout::Error, "Workflow #{workflow_id} did not complete within #{timeout_seconds} seconds" if Time.now >= deadline

          sleep(poll_interval_seconds)
        end
      end

      # Execute a workflow and wait for completion (with polling fallback)
      # @param [String] name Workflow name
      # @param [Hash] input Workflow input
      # @param [Integer] timeout_seconds Maximum time to wait
      # @param [Hash] options Additional options (version, correlation_id, etc.)
      # @return [Workflow] Completed workflow
      def execute_and_wait(name, input: {}, timeout_seconds: 60, **options)
        # First try synchronous execution
        result = execute(
          name,
          input: input,
          wait_for_seconds: [timeout_seconds, 30].min, # Server-side wait capped at 30s typically
          **options
        )

        # If still running, poll for completion
        if result.running?
          wait_for_workflow(result.workflow_id, timeout_seconds: timeout_seconds)
        else
          get_workflow(result.workflow_id)
        end
      end
    end
  end
end
