# frozen_string_literal: true

module Conductor
  module Worker
    module Events
      # Listener protocol for task runner events.
      # All methods are optional - the dispatcher uses duck typing (respond_to?).
      module TaskRunnerEventsListener
        def on_poll_started(event); end
        def on_poll_completed(event); end
        def on_poll_failure(event); end
        def on_task_execution_started(event); end
        def on_task_execution_completed(event); end
        def on_task_execution_failure(event); end
        def on_task_update_completed(event); end
        def on_task_update_failure(event); end
        def on_task_paused(event); end
        def on_thread_uncaught_exception(event); end
        def on_active_workers_changed(event); end
      end

      # Listener protocol for workflow-lifecycle events
      module WorkflowEventsListener
        def on_workflow_start_error(event); end
        def on_workflow_input_size(event); end
      end

      # Listener protocol for HTTP API client events
      module HttpEventsListener
        def on_http_api_request(event); end
      end
    end
  end
end
