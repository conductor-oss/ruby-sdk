# frozen_string_literal: true

require_relative 'sync_event_dispatcher'

module Conductor
  module Worker
    module Events
      # Process-wide default event dispatcher.
      #
      # Used by library layers (e.g. HTTP client) that don't have an obvious
      # owner to receive a dispatcher reference. Listeners can subscribe to this
      # singleton to receive events regardless of which RestClient/ApiClient
      # instance generated them.
      class GlobalDispatcher
        class << self
          def instance
            @instance ||= SyncEventDispatcher.new
          end

          def reset!
            @instance = SyncEventDispatcher.new
          end

          def publish(event)
            instance.publish(event)
          end
        end
      end
    end
  end
end
