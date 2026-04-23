# frozen_string_literal: true

require_relative 'conductor_event'

module Conductor
  module Worker
    module Events
      # Published from the HTTP client middleware on every API request
      # Maps to canonical http_api_client_request_seconds{method, uri, status}
      class HttpApiRequest < ConductorEvent
        # @return [String] HTTP method (GET, POST, ...)
        attr_reader :method
        # @return [String] Interpolated request path / URI
        attr_reader :uri
        # @return [String] HTTP status code as a string, or "0" on network failure
        attr_reader :status
        # @return [Float] Duration of the request in milliseconds
        attr_reader :duration_ms

        # @param method [String] HTTP method
        # @param uri [String] Request path / URI
        # @param status [String, Integer] HTTP status code ("0" if network failure)
        # @param duration_ms [Float] Duration in milliseconds
        def initialize(method:, uri:, status:, duration_ms:)
          super()
          @method = method.to_s.upcase
          @uri = uri.to_s
          @status = status.to_s
          @duration_ms = duration_ms
        end

        def to_h
          super.merge(
            method: @method,
            uri: @uri,
            status: @status,
            duration_ms: @duration_ms
          )
        end
      end
    end
  end
end
