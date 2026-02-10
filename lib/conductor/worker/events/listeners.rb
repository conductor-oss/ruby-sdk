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

        # Called when task update fails after all retries (CRITICAL)
        # @param event [TaskUpdateFailure]
        def on_task_update_failure(event); end
      end
    end
  end
end
