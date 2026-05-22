# frozen_string_literal: true

require_relative 'conductor_event'

module Conductor
  module Worker
    module Events
      class HttpApiRequest < ConductorEvent
        attr_reader :method, :uri, :status, :duration_ms

        def initialize(method:, uri:, status:, duration_ms:)
          super()
          @method = method.to_s.upcase
          @uri = uri.to_s
          @status = status.to_s
          @duration_ms = duration_ms
        end

        def to_h
          super.merge(method: @method, uri: @uri, status: @status, duration_ms: @duration_ms)
        end
      end
    end
  end
end
