# frozen_string_literal: true

module Conductor
  module Worker
    module Events
      # Thread-safe synchronous event dispatcher
      # Dispatches events to registered listeners in the calling thread
      # Listener exceptions are isolated and logged, never propagating to callers
      class SyncEventDispatcher
        def initialize
          @listeners = Hash.new { |h, k| h[k] = [] }
          @mutex = Mutex.new
        end

        # Register a listener for an event type
        # @param event_type [Class] Event class to listen for
        # @param listener [Proc, #call] Callable to invoke when event is published
        # @return [self]
        def register(event_type, listener)
          @mutex.synchronize do
            @listeners[event_type] << listener unless @listeners[event_type].include?(listener)
          end
          self
        end

        # Unregister a listener for an event type
        # @param event_type [Class] Event class
        # @param listener [Proc, #call] Listener to remove
        # @return [self]
        def unregister(event_type, listener)
          @mutex.synchronize do
            @listeners[event_type].delete(listener)
          end
          self
        end

        # Publish an event to all registered listeners
        # Listeners are called synchronously in the calling thread
        # Exceptions in listeners are caught and logged, not propagated
        # @param event [ConductorEvent] Event to publish
        # @return [self]
        def publish(event)
          listeners = @mutex.synchronize { @listeners[event.class].dup }

          listeners.each do |listener|
            begin
              listener.call(event)
            rescue StandardError => e
              # Listener failure is isolated - never breaks the worker
              warn "[Conductor] Event listener error for #{event.class}: #{e.message}"
            end
          end

          self
        end

        # Check if there are listeners registered for an event type
        # @param event_type [Class] Event class
        # @return [Boolean]
        def has_listeners?(event_type)
          @mutex.synchronize { @listeners[event_type].any? }
        end

        # Get the number of listeners for an event type
        # @param event_type [Class] Event class
        # @return [Integer]
        def listener_count(event_type)
          @mutex.synchronize { @listeners[event_type].size }
        end

        # Clear all listeners (primarily for testing)
        # @return [self]
        def clear
          @mutex.synchronize { @listeners.clear }
          self
        end
      end
    end
  end
end
