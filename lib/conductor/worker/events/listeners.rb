# frozen_string_literal: true

module Conductor
  module Worker
    module Events
      # Listener protocol for task runner events
      # Include this module to document the expected interface
      # All methods are optional - only implement the ones you need
      # The dispatcher uses duck typing (respond_to?) to check for methods
      module TaskRunnerEventsListener
        # Called when polling starts
        # @param event [PollStarted]
        def on_poll_started(event); end

        # Called when polling completes successfully
        # @param event [PollCompleted]
        def on_poll_completed(event); end

        # Called when polling fails
        # @param event [PollFailure]
        def on_poll_failure(event); end

        # Called when task execution starts
        # @param event [TaskExecutionStarted]
        def on_task_execution_started(event); end

        # Called when task execution completes successfully
        # @param event [TaskExecutionCompleted]
        def on_task_execution_completed(event); end

        # Called when task execution fails
        # @param event [TaskExecutionFailure]
        def on_task_execution_failure(event); end

        # Called when task update completes successfully
        # @param event [TaskUpdateCompleted]
        def on_task_update_completed(event); end

        # Called when task update fails after all retries (CRITICAL)
        # @param event [TaskUpdateFailure]
        def on_task_update_failure(event); end

        # Called when a poll iteration is skipped because the worker is paused
        # @param event [TaskPaused]
        def on_task_paused(event); end

        # Called when a worker thread terminates with an uncaught exception
        # @param event [ThreadUncaughtException]
        def on_thread_uncaught_exception(event); end

        # Called when the active-worker count changes for a task type
        # @param event [ActiveWorkersChanged]
        def on_active_workers_changed(event); end
      end

      # Listener protocol for workflow-lifecycle events
      module WorkflowEventsListener
        # Called when a StartWorkflow call fails client-side
        # @param event [WorkflowStartError]
        def on_workflow_start_error(event); end

        # Called after a workflow input payload is serialized (with byte size)
        # @param event [WorkflowInputSize]
        def on_workflow_input_size(event); end
      end

      # Listener protocol for HTTP API client events
      module HttpEventsListener
        # Called on every HTTP request made by the generated API client
        # @param event [HttpApiRequest]
        def on_http_api_request(event); end
      end
    end
  end
end
