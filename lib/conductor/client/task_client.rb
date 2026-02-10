# frozen_string_literal: true

require_relative '../configuration'
require_relative '../http/api_client'
require_relative '../http/api/task_resource_api'

module Conductor
  module Client
    # TaskClient - High-level client for task operations
    class TaskClient
      attr_reader :task_api

      # Initialize TaskClient
      # @param [Configuration] configuration Optional configuration
      def initialize(configuration = nil)
        @configuration = configuration || Configuration.new
        api_client = Http::ApiClient.new(configuration: @configuration)
        @task_api = Http::Api::TaskResourceApi.new(api_client)
      end

      # Poll for a task
      # @param [String] task_type Task type to poll
      # @param [String] worker_id Worker ID (optional)
      # @param [String] domain Domain (optional)
      # @return [Task, nil] Task object or nil if no task available
      def poll_task(task_type, worker_id: nil, domain: nil)
        @task_api.poll(task_type, worker_id: worker_id, domain: domain)
      end

      # Batch poll for tasks
      # @param [String] task_type Task type to poll
      # @param [Integer] count Number of tasks to poll (default: 1)
      # @param [Integer] timeout Timeout in milliseconds (default: 100)
      # @param [String] worker_id Worker ID (optional)
      # @param [String] domain Domain (optional)
      # @return [Array<Task>] Array of tasks
      def batch_poll_tasks(task_type, count: 1, timeout: 100, worker_id: nil, domain: nil)
        @task_api.batch_poll(task_type, count: count, timeout: timeout, worker_id: worker_id, domain: domain)
      end

      # Update task status
      # @param [TaskResult] task_result Task result
      # @return [String] Task ID
      def update_task(task_result)
        @task_api.update_task(task_result)
      end

      # Get task details
      # @param [String] task_id Task ID
      # @return [Task] Task object
      def get_task(task_id)
        @task_api.get_task(task_id)
      end

      # Remove task from queue
      # @param [String] task_type Task type
      # @param [String] task_id Task ID
      # @return [void]
      def remove_task_from_queue(task_type, task_id)
        @task_api.remove_task_from_queue(task_type, task_id)
      end

      # Get queue sizes for task types
      # @param [Array<String>] task_types List of task types (optional)
      # @return [Hash<String, Integer>] Map of task type to queue size
      def get_queue_sizes(task_types: nil)
        @task_api.size(task_types: task_types)
      end

      # Get all queue details
      # @return [Hash<String, Integer>] Map of task type to queue size
      def get_all_queue_details
        @task_api.all_queue_details
      end

      # Get queue details for a specific task type
      # @param [String] task_type Task type
      # @return [Hash] Queue details
      def get_queue_details(task_type)
        @task_api.get_task_queue_details(task_type)
      end

      # Add task execution log
      # @param [String] task_id Task ID
      # @param [String] log_message Log message
      # @return [void]
      def add_task_log(task_id, log_message)
        @task_api.log(task_id, log_message)
      end

      # Get task execution logs
      # @param [String] task_id Task ID
      # @return [Array<TaskExecLog>] Array of task execution logs
      def get_task_logs(task_id)
        @task_api.get_task_logs(task_id)
      end

      # Get pending tasks for a task type
      # @param [String] task_type Task type
      # @param [Integer] start Start index (default: 0)
      # @param [Integer] count Number of tasks (default: 100)
      # @return [Array<Task>] Array of pending tasks
      def get_pending_tasks(task_type, start: 0, count: 100)
        @task_api.get_pending_task_for_task_type(task_type, start: start, count: count)
      end

      # Update task by reference name
      # @param [String] workflow_id Workflow ID
      # @param [String] task_ref_name Task reference name
      # @param [String] status New status
      # @param [Hash] output Task output data (optional)
      # @param [String] worker_id Worker ID (optional)
      # @return [String] Updated workflow ID
      def update_task_by_ref_name(workflow_id, task_ref_name, status, output: nil, worker_id: nil)
        @task_api.update_task_by_ref_name(workflow_id, task_ref_name, status, output: output, worker_id: worker_id)
      end

      # Update task by reference name synchronously (returns workflow state)
      # @param [String] workflow_id Workflow ID
      # @param [String] task_ref_name Task reference name
      # @param [String] status New status
      # @param [Hash] output Task output data (optional)
      # @param [String] worker_id Worker ID (optional)
      # @return [Workflow] Updated workflow
      def update_task_sync(workflow_id, task_ref_name, status, output: nil, worker_id: nil)
        @task_api.update_task_sync(workflow_id, task_ref_name, status, output: output, worker_id: worker_id)
      end

      # Get poll data for a task type
      # @param [String] task_type Task type name
      # @return [Array<PollData>]
      def get_task_poll_data(task_type)
        @task_api.get_poll_data(task_type)
      end

      # Get all poll data
      # @return [Array<PollData>]
      def get_all_poll_data
        @task_api.get_all_poll_data
      end

      # Requeue pending tasks
      # @param [String] task_type Task type name
      # @return [String]
      def requeue_pending_task(task_type)
        @task_api.requeue_pending_task(task_type)
      end

      # Search for tasks
      # @param [Integer] start Start index (default: 0)
      # @param [Integer] size Page size (default: 100)
      # @param [String] sort Sort order (optional)
      # @param [String] free_text Free text search (default: '*')
      # @param [String] query Query string (optional)
      # @return [SearchResult]
      def search(start: 0, size: 100, sort: nil, free_text: '*', query: nil)
        @task_api.search(start: start, size: size, sort: sort, free_text: free_text, query: query)
      end

      # Get queue sizes for specific task types
      # @param [Array<String>] task_types List of task type names
      # @return [Hash<String, Integer>]
      def get_queue_sizes_for_tasks(task_types)
        @task_api.get_queue_sizes_for_tasks(task_types)
      end
    end
  end
end
