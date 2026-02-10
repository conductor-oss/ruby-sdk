# frozen_string_literal: true

require_relative 'task_runner_events'

module Conductor
  module Worker
    module Events
      # Helper class to register listener objects with event dispatchers
      # Uses duck typing to detect which methods a listener implements
      class ListenerRegistry
        # Mapping of event classes to listener method names
        EVENT_METHOD_MAP = {
          PollStarted => :on_poll_started,
          PollCompleted => :on_poll_completed,
          PollFailure => :on_poll_failure,
          TaskExecutionStarted => :on_task_execution_started,
          TaskExecutionCompleted => :on_task_execution_completed,
          TaskExecutionFailure => :on_task_execution_failure,
          TaskUpdateFailure => :on_task_update_failure
        }.freeze

        # Register a listener object with the dispatcher
        # Auto-detects implemented methods via respond_to?
        # @param listener [Object] Object implementing TaskRunnerEventsListener methods
        # @param dispatcher [SyncEventDispatcher] Event dispatcher
        # @return [void]
        def self.register_task_runner_listener(listener, dispatcher)
          EVENT_METHOD_MAP.each do |event_class, method_name|
            if listener.respond_to?(method_name)
              dispatcher.register(event_class, ->(event) { listener.send(method_name, event) })
            end
          end
        end

        # Register multiple listeners with the dispatcher
        # @param listeners [Array<Object>] Array of listener objects
        # @param dispatcher [SyncEventDispatcher] Event dispatcher
        # @return [void]
        def self.register_all(listeners, dispatcher)
          listeners.each do |listener|
            register_task_runner_listener(listener, dispatcher)
          end
        end
      end
    end
  end
end
