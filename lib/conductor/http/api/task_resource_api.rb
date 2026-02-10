# frozen_string_literal: true

require_relative '../api_client'

module Conductor
  module Http
    module Api
      # TaskResourceApi - API for task operations
      class TaskResourceApi
        attr_accessor :api_client

        # Initialize TaskResourceApi
        # @param [ApiClient] api_client Optional API client
        def initialize(api_client = nil)
          @api_client = api_client || ApiClient.new
        end

        # Poll for a task of a certain type
        # @param [String] task_type Task type to poll
        # @param [String] worker_id Worker ID (optional)
        # @param [String] domain Domain (optional)
        # @return [Task, nil] Task object or nil if no task available
        def poll(task_type, worker_id: nil, domain: nil)
          query_params = {}
          query_params[:workerid] = worker_id if worker_id
          query_params[:domain] = domain if domain

          @api_client.call_api(
            '/tasks/poll/{taskType}',
            'GET',
            path_params: { taskType: task_type },
            query_params: query_params,
            return_type: 'Task',
            return_http_data_only: true
          )
        end

        # Batch poll for tasks
        # @param [String] task_type Task type to poll
        # @param [Integer] count Number of tasks to poll (default: 1, max: 100)
        # @param [Integer] timeout Timeout in milliseconds (default: 100)
        # @param [String] worker_id Worker ID (optional)
        # @param [String] domain Domain (optional)
        # @return [Array<Task>] Array of tasks
        def batch_poll(task_type, count: 1, timeout: 100, worker_id: nil, domain: nil)
          query_params = {
            count: [count, 100].min,
            timeout: timeout
          }
          query_params[:workerid] = worker_id if worker_id
          query_params[:domain] = domain if domain

          @api_client.call_api(
            '/tasks/poll/batch/{taskType}',
            'GET',
            path_params: { taskType: task_type },
            query_params: query_params,
            return_type: 'Array<Task>',
            return_http_data_only: true
          )
        end

        # Update task status
        # @param [TaskResult] body Task result
        # @return [String] Task ID
        def update_task(body)
          @api_client.call_api(
            '/tasks',
            'POST',
            body: body,
            return_type: 'String',
            return_http_data_only: true
          )
        end

        # Get task details
        # @param [String] task_id Task ID
        # @return [Task] Task object
        def get_task(task_id)
          @api_client.call_api(
            '/tasks/{taskId}',
            'GET',
            path_params: { taskId: task_id },
            return_type: 'Task',
            return_http_data_only: true
          )
        end

        # Remove task from queue
        # @param [String] task_type Task type
        # @param [String] task_id Task ID
        # @return [void]
        def remove_task_from_queue(task_type, task_id)
          @api_client.call_api(
            '/tasks/queue/{taskType}/{taskId}',
            'DELETE',
            path_params: { taskType: task_type, taskId: task_id },
            return_http_data_only: true
          )
        end

        # Get task queue sizes
        # @param [Array<String>] task_types List of task types (optional)
        # @return [Hash<String, Integer>] Map of task type to queue size
        def size(task_types: nil)
          @api_client.call_api(
            '/tasks/queue/sizes',
            'POST',
            body: task_types || [],
            return_type: 'Hash<String, Integer>',
            return_http_data_only: true
          )
        end

        # Get all queue details
        # @return [Hash<String, Integer>] Map of task type to queue size
        def all_queue_details
          @api_client.call_api(
            '/tasks/queue/all',
            'GET',
            return_type: 'Hash<String, Integer>',
            return_http_data_only: true
          )
        end

        # Get queue details for a task type
        # @param [String] task_type Task type
        # @return [Hash] Queue details
        def get_task_queue_details(task_type)
          @api_client.call_api(
            '/tasks/queue/all/{taskType}',
            'GET',
            path_params: { taskType: task_type },
            return_type: 'Hash<String, Object>',
            return_http_data_only: true
          )
        end

        # Add task execution log
        # @param [String] task_id Task ID
        # @param [String] log Log message
        # @return [void]
        def log(task_id, log)
          @api_client.call_api(
            '/tasks/{taskId}/log',
            'POST',
            path_params: { taskId: task_id },
            body: log,
            return_http_data_only: true
          )
        end

        # Get task execution logs
        # @param [String] task_id Task ID
        # @return [Array<TaskExecLog>] Array of task execution logs
        def get_task_logs(task_id)
          @api_client.call_api(
            '/tasks/{taskId}/log',
            'GET',
            path_params: { taskId: task_id },
            return_type: 'Array<TaskExecLog>',
            return_http_data_only: true
          )
        end

        # Get pending tasks for a task type
        # @param [String] task_type Task type
        # @param [Integer] start Start index (default: 0)
        # @param [Integer] count Number of tasks (default: 100)
        # @return [Array<Task>] Array of pending tasks
        def get_pending_task_for_task_type(task_type, start: 0, count: 100)
          @api_client.call_api(
            '/tasks/in_progress/{taskType}',
            'GET',
            path_params: { taskType: task_type },
            query_params: { start: start, count: count },
            return_type: 'Array<Task>',
            return_http_data_only: true
          )
        end

        # Update task by reference name
        # @param [String] workflow_id Workflow ID
        # @param [String] task_ref_name Task reference name
        # @param [String] status New status
        # @param [Hash] output Task output data (optional)
        # @param [String] worker_id Worker ID (optional)
        # @return [String] Updated workflow ID
        def update_task_by_ref_name(workflow_id, task_ref_name, status, output: nil, worker_id: nil)
          query_params = {}
          query_params[:workerid] = worker_id if worker_id

          @api_client.call_api(
            '/tasks/{workflowId}/{taskRefName}/{status}',
            'POST',
            path_params: {
              workflowId: workflow_id,
              taskRefName: task_ref_name,
              status: status
            },
            query_params: query_params,
            body: output || {},
            return_type: 'String',
            return_http_data_only: true
          )
        end

        # Update task by reference name synchronously (returns workflow state)
        # @param [String] workflow_id Workflow ID
        # @param [String] task_ref_name Task reference name
        # @param [String] status New status
        # @param [Hash] output Task output data
        # @param [String] worker_id Worker ID (optional)
        # @return [Workflow] Updated workflow
        def update_task_sync(workflow_id, task_ref_name, status, output: nil, worker_id: nil)
          query_params = {}
          query_params[:workerid] = worker_id if worker_id

          @api_client.call_api(
            '/tasks/{workflowId}/{taskRefName}/{status}/sync',
            'POST',
            path_params: {
              workflowId: workflow_id,
              taskRefName: task_ref_name,
              status: status
            },
            query_params: query_params,
            body: output || {},
            return_type: 'Workflow',
            return_http_data_only: true
          )
        end

        # Get all queue details (verbose)
        # @return [Hash] Verbose queue details
        def all_verbose
          @api_client.call_api(
            '/tasks/queue/all/verbose',
            'GET',
            return_type: 'Hash<String, Object>',
            return_http_data_only: true
          )
        end

        # Get queue sizes for specific task types
        # @param [Array<String>] task_types List of task type names
        # @return [Hash<String, Integer>]
        def get_queue_sizes_for_tasks(task_types)
          query_params = {}
          query_params[:taskType] = task_types if task_types&.any?

          @api_client.call_api(
            '/tasks/queue/sizes',
            'GET',
            query_params: query_params,
            return_type: 'Hash<String, Integer>',
            return_http_data_only: true
          )
        end

        # Get poll data for a task type
        # @param [String] task_type Task type name
        # @return [Array<PollData>]
        def get_poll_data(task_type)
          @api_client.call_api(
            '/tasks/queue/polldata',
            'GET',
            query_params: { taskType: task_type },
            return_type: 'Array<PollData>',
            return_http_data_only: true
          )
        end

        # Get all poll data
        # @return [Array<PollData>]
        def get_all_poll_data
          @api_client.call_api(
            '/tasks/queue/polldata/all',
            'GET',
            return_type: 'Array<PollData>',
            return_http_data_only: true
          )
        end

        # Requeue pending tasks of a type
        # @param [String] task_type Task type name
        # @return [String]
        def requeue_pending_task(task_type)
          @api_client.call_api(
            '/tasks/queue/requeue/{taskType}',
            'POST',
            path_params: { taskType: task_type },
            return_type: 'String',
            return_http_data_only: true
          )
        end

        # Search for tasks
        # @param [Integer] start Start index (default: 0)
        # @param [Integer] size Page size (default: 100)
        # @param [String] sort Sort order (optional)
        # @param [String] free_text Free text search (default: '*')
        # @param [String] query Query string (optional)
        # @return [SearchResult]
        def search(start: 0, size: 100, sort: nil, free_text: '*', query: nil)
          query_params = { start: start, size: size, freeText: free_text }
          query_params[:sort] = sort if sort
          query_params[:query] = query if query

          @api_client.call_api(
            '/tasks/search',
            'GET',
            query_params: query_params,
            return_type: 'SearchResult',
            return_http_data_only: true
          )
        end
      end
    end
  end
end
