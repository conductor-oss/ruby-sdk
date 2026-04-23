# frozen_string_literal: true

require_relative 'sync_event_dispatcher'

module Conductor
  module Worker
    module Events
      # Process-wide default event dispatcher.
      #
      # Used by client-library layers (e.g. HTTP client) that don't have an obvious
      # owner to receive a dispatcher reference. Listeners can subscribe to this
      # singleton to receive events regardless of which RestClient/ApiClient instance
      # generated them. The TaskHandler's per-instance dispatcher is still used
      # for worker-loop events (PollStarted, TaskExecutionCompleted, etc.).
      #
      # This is intentionally minimal: no auto-wiring, no magic. Consumers that need
      # isolation (tests, multi-tenant processes) can call `.reset!` between usages.
      class GlobalDispatcher
        class << self
          # @return [SyncEventDispatcher] Process-wide dispatcher instance
          def instance
            @instance ||= SyncEventDispatcher.new
          end

          # Replace the current global dispatcher with a fresh one.
          # Primarily for testing.
          # @return [SyncEventDispatcher] The new dispatcher instance
          def reset!
            @instance = SyncEventDispatcher.new
          end

          # Publish an event to the process-wide dispatcher.
          # @param event [ConductorEvent]
          def publish(event)
            instance.publish(event)
          end
        end
      end
    end
  end
end
