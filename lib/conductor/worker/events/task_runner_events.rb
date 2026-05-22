# frozen_string_literal: true

require_relative 'conductor_event'

module Conductor
  module Worker
    module Events
      # Published when polling starts
      class PollStarted < TaskRunnerEvent
        # @return [String] Unique worker identifier
        attr_reader :worker_id
        # @return [Integer] Number of polls performed so far
        attr_reader :poll_count

        # @param task_type [String] Task definition name
        # @param worker_id [String] Unique worker identifier
        # @param poll_count [Integer] Number of polls performed
        def initialize(task_type:, worker_id:, poll_count:)
          super(task_type: task_type)
          @worker_id = worker_id
          @poll_count = poll_count
        end

        def to_h
          super.merge(worker_id: @worker_id, poll_count: @poll_count)
        end
      end

      # Published when polling completes successfully
      class PollCompleted < TaskRunnerEvent
        # @return [Float] Duration of poll in milliseconds
        attr_reader :duration_ms
        # @return [Integer] Number of tasks received
        attr_reader :tasks_received

        # @param task_type [String] Task definition name
        # @param duration_ms [Float] Duration of poll in milliseconds
        # @param tasks_received [Integer] Number of tasks received
        def initialize(task_type:, duration_ms:, tasks_received:)
          super(task_type: task_type)
          @duration_ms = duration_ms
          @tasks_received = tasks_received
        end

        def to_h
          super.merge(duration_ms: @duration_ms, tasks_received: @tasks_received)
        end
      end

      # Published when polling fails
      class PollFailure < TaskRunnerEvent
        # @return [Float] Duration of poll in milliseconds
        attr_reader :duration_ms
        # @return [Exception] The exception that caused the failure
        attr_reader :cause

        # @param task_type [String] Task definition name
        # @param duration_ms [Float] Duration of poll in milliseconds
        # @param cause [Exception] The exception that caused the failure
        def initialize(task_type:, duration_ms:, cause:)
          super(task_type: task_type)
          @duration_ms = duration_ms
          @cause = cause
        end

        def to_h
          super.merge(
            duration_ms: @duration_ms,
            cause: @cause.class.name,
            cause_message: @cause.message
          )
        end
      end

      # Published when task execution starts
      class TaskExecutionStarted < TaskRunnerEvent
        # @return [String] Unique task identifier
        attr_reader :task_id
        # @return [String] Unique worker identifier
        attr_reader :worker_id
        # @return [String] Workflow instance identifier
        attr_reader :workflow_instance_id

        # @param task_type [String] Task definition name
        # @param task_id [String] Unique task identifier
        # @param worker_id [String] Unique worker identifier
        # @param workflow_instance_id [String] Workflow instance identifier
        def initialize(task_type:, task_id:, worker_id:, workflow_instance_id:)
          super(task_type: task_type)
          @task_id = task_id
          @worker_id = worker_id
          @workflow_instance_id = workflow_instance_id
        end

        def to_h
          super.merge(
            task_id: @task_id,
            worker_id: @worker_id,
            workflow_instance_id: @workflow_instance_id
          )
        end
      end

      # Published when task execution completes successfully
      class TaskExecutionCompleted < TaskRunnerEvent
        # @return [String] Unique task identifier
        attr_reader :task_id
        # @return [String] Unique worker identifier
        attr_reader :worker_id
        # @return [String] Workflow instance identifier
        attr_reader :workflow_instance_id
        # @return [Float] Duration of execution in milliseconds
        attr_reader :duration_ms
        # @return [Integer, nil] Size of output data in bytes
        attr_reader :output_size_bytes

        # @param task_type [String] Task definition name
        # @param task_id [String] Unique task identifier
        # @param worker_id [String] Unique worker identifier
        # @param workflow_instance_id [String] Workflow instance identifier
        # @param duration_ms [Float] Duration of execution in milliseconds
        # @param output_size_bytes [Integer, nil] Size of output data in bytes
        def initialize(task_type:, task_id:, worker_id:, workflow_instance_id:,
                       duration_ms:, output_size_bytes: nil)
          super(task_type: task_type)
          @task_id = task_id
          @worker_id = worker_id
          @workflow_instance_id = workflow_instance_id
          @duration_ms = duration_ms
          @output_size_bytes = output_size_bytes
        end

        def to_h
          super.merge(
            task_id: @task_id,
            worker_id: @worker_id,
            workflow_instance_id: @workflow_instance_id,
            duration_ms: @duration_ms,
            output_size_bytes: @output_size_bytes
          )
        end
      end

      # Published when task execution fails
      class TaskExecutionFailure < TaskRunnerEvent
        # @return [String] Unique task identifier
        attr_reader :task_id
        # @return [String] Unique worker identifier
        attr_reader :worker_id
        # @return [String] Workflow instance identifier
        attr_reader :workflow_instance_id
        # @return [Float] Duration of execution in milliseconds
        attr_reader :duration_ms
        # @return [Exception] The exception that caused the failure
        attr_reader :cause
        # @return [Boolean] Whether the error is retryable
        attr_reader :is_retryable

        # @param task_type [String] Task definition name
        # @param task_id [String] Unique task identifier
        # @param worker_id [String] Unique worker identifier
        # @param workflow_instance_id [String] Workflow instance identifier
        # @param duration_ms [Float] Duration of execution in milliseconds
        # @param cause [Exception] The exception that caused the failure
        # @param is_retryable [Boolean] Whether the error is retryable (default: true)
        def initialize(task_type:, task_id:, worker_id:, workflow_instance_id:,
                       duration_ms:, cause:, is_retryable: true)
          super(task_type: task_type)
          @task_id = task_id
          @worker_id = worker_id
          @workflow_instance_id = workflow_instance_id
          @duration_ms = duration_ms
          @cause = cause
          @is_retryable = is_retryable
        end

        def to_h
          super.merge(
            task_id: @task_id,
            worker_id: @worker_id,
            workflow_instance_id: @workflow_instance_id,
            duration_ms: @duration_ms,
            cause: @cause.class.name,
            cause_message: @cause.message,
            is_retryable: @is_retryable
          )
        end
      end

      # Published when task update completes successfully
      class TaskUpdateCompleted < TaskRunnerEvent
        attr_reader :task_id, :worker_id, :workflow_instance_id, :duration_ms

        def initialize(task_type:, task_id:, worker_id:, workflow_instance_id:, duration_ms:)
          super(task_type: task_type)
          @task_id = task_id
          @worker_id = worker_id
          @workflow_instance_id = workflow_instance_id
          @duration_ms = duration_ms
        end

        def to_h
          super.merge(
            task_id: @task_id, worker_id: @worker_id,
            workflow_instance_id: @workflow_instance_id, duration_ms: @duration_ms
          )
        end
      end

      # Published when task update fails after all retries
      # This is a CRITICAL event - the task result is lost
      class TaskUpdateFailure < TaskRunnerEvent
        attr_reader :task_id, :worker_id, :workflow_instance_id,
                    :cause, :retry_count, :task_result, :duration_ms

        def initialize(task_type:, task_id:, worker_id:, workflow_instance_id:,
                       cause:, retry_count:, task_result:, duration_ms: nil)
          super(task_type: task_type)
          @task_id = task_id
          @worker_id = worker_id
          @workflow_instance_id = workflow_instance_id
          @cause = cause
          @retry_count = retry_count
          @task_result = task_result
          @duration_ms = duration_ms
        end

        def to_h
          super.merge(
            task_id: @task_id, worker_id: @worker_id,
            workflow_instance_id: @workflow_instance_id,
            cause: @cause.class.name, cause_message: @cause.message,
            retry_count: @retry_count, duration_ms: @duration_ms
          )
        end
      end

      # Published when a poll iteration is skipped because the worker is paused
      class TaskPaused < TaskRunnerEvent; end

      # Published when a worker thread terminates with an uncaught exception
      class ThreadUncaughtException < ConductorEvent
        attr_reader :cause, :task_type

        def initialize(cause:, task_type: nil)
          super()
          @cause = cause
          @task_type = task_type
        end

        def to_h
          super.merge(cause: @cause.class.name, cause_message: @cause.message, task_type: @task_type)
        end
      end

      # Published when the active-worker count changes for a task type
      class ActiveWorkersChanged < TaskRunnerEvent
        attr_reader :count

        def initialize(task_type:, count:)
          super(task_type: task_type)
          @count = count
        end

        def to_h
          super.merge(count: @count)
        end
      end
    end
  end
end
