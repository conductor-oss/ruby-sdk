# frozen_string_literal: true

require_relative 'task_runner_events'
require_relative 'workflow_events'
require_relative 'http_events'

module Conductor
  module Worker
    module Events
      class ListenerRegistry
        EVENT_METHOD_MAP = {
          PollStarted => :on_poll_started,
          PollCompleted => :on_poll_completed,
          PollFailure => :on_poll_failure,
          TaskExecutionStarted => :on_task_execution_started,
          TaskExecutionCompleted => :on_task_execution_completed,
          TaskExecutionFailure => :on_task_execution_failure,
          TaskUpdateCompleted => :on_task_update_completed,
          TaskUpdateFailure => :on_task_update_failure,
          TaskPaused => :on_task_paused,
          ThreadUncaughtException => :on_thread_uncaught_exception,
          ActiveWorkersChanged => :on_active_workers_changed,
          WorkflowStartError => :on_workflow_start_error,
          WorkflowInputSize => :on_workflow_input_size,
          HttpApiRequest => :on_http_api_request
        }.freeze

        def self.register_task_runner_listener(listener, dispatcher)
          EVENT_METHOD_MAP.each do |event_class, method_name|
            dispatcher.register(event_class, ->(event) { listener.send(method_name, event) }) if listener.respond_to?(method_name)
          end
        end

        def self.register_all(listeners, dispatcher)
          listeners.each { |listener| register_task_runner_listener(listener, dispatcher) }
        end
      end
    end
  end
end
