# frozen_string_literal: true

module Conductor
  module Worker
    # Provides execution context for workers
    # Accessible from anywhere in worker code via TaskContext.current
    # Stored in thread-local storage (Thread.current)
    class TaskContext
      # @return [Task] The task being executed
      attr_reader :task

      # @return [TaskResult] The task result being built
      attr_reader :task_result

      # Get the current task context (thread-local)
      # @return [TaskContext, nil] Current context or nil if not in a task execution
      def self.current
        Thread.current[:conductor_task_context]
      end

      # Set the current task context (internal use by TaskRunner)
      # @param context [TaskContext, nil]
      # @return [void]
      def self.current=(context)
        Thread.current[:conductor_task_context] = context
      end

      # Clear the current task context (internal use by TaskRunner)
      # @return [void]
      def self.clear
        Thread.current[:conductor_task_context] = nil
      end

      # Initialize a new task context
      # @param task [Task] The task being executed
      # @param task_result [TaskResult] The task result being built
      def initialize(task, task_result)
        @task = task
        @task_result = task_result
      end

      # Get the task ID
      # @return [String]
      def task_id
        @task.task_id
      end

      # Get the workflow instance ID
      # @return [String]
      def workflow_instance_id
        @task.workflow_instance_id
      end

      # Get the retry count (how many times this task has been retried)
      # @return [Integer]
      def retry_count
        @task.retry_count || 0
      end

      # Get the poll count (how many times this task has been polled for long-running tasks)
      # @return [Integer]
      def poll_count
        @task.poll_count || 0
      end

      # Get the task input data
      # @return [Hash]
      def input
        @task.input_data || {}
      end

      # Get the task definition name
      # @return [String]
      def task_def_name
        @task.task_def_name || @task.task_type
      end

      # Get the workflow task type
      # @return [String]
      def workflow_task_type
        @task.workflow_task&.type || @task.task_type
      end

      # Add a log message to the task result
      # Logs are visible in the Conductor UI
      # @param message [String] Log message
      # @return [void]
      def add_log(message)
        @task_result.log(message)
      end

      # Set the callback_after_seconds for long-running tasks
      # When returning TaskInProgress, this determines when Conductor will poll again
      # @param seconds [Integer] Seconds to wait before polling again
      # @return [void]
      def set_callback_after(seconds)
        @task_result.callback_after_seconds = seconds
      end

      # Get the callback_after_seconds value
      # @return [Integer, nil]
      def callback_after_seconds
        @task_result.callback_after_seconds
      end

      # Set the output data on the task result
      # @param output_data [Hash] Output data
      # @return [void]
      def set_output(output_data)
        @task_result.output_data = output_data
      end
    end
  end
end
