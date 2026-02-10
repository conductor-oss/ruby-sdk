# frozen_string_literal: true

module Conductor
  # Base exception for all Conductor errors
  class ConductorError < StandardError; end

  # Configuration error (invalid settings, missing dependencies)
  class ConfigurationError < ConductorError; end

  # API-level exception (HTTP errors from server)
  class ApiError < ConductorError
    attr_reader :status, :code, :reason, :body, :headers

    def initialize(message = nil, status: nil, code: nil, reason: nil, body: nil, headers: nil)
      @status = status
      @code = code || status
      @reason = reason
      @body = body
      @headers = headers
      super(message || build_message)
    end

    def not_found?
      @code == 404
    end

    private

    def build_message
      msg = "(#{@status}) #{@reason}"
      msg += "\nBody: #{@body}" if @body
      msg
    end
  end

  # Authorization error (401/403 with special token handling)
  class AuthorizationError < ApiError
    attr_reader :error_code

    def initialize(message = nil, status: nil, body: nil, headers: nil)
      @error_code = parse_error_code(body)
      super(message, status: status, body: body, headers: headers)
    end

    def token_expired?
      @error_code == 'EXPIRED_TOKEN'
    end

    def invalid_token?
      @error_code == 'INVALID_TOKEN'
    end

    private

    def parse_error_code(body)
      return nil unless body

      data = JSON.parse(body) rescue nil
      data&.dig('error') || ''
    end

    def build_message
      msg = "Authorization error: #{@error_code} (status: #{@status})"
      msg += "\nReason: #{@reason}" if @reason
      msg += "\nBody: #{@body}" if @body
      msg
    end
  end

  # Non-retryable worker error (terminal failure)
  class NonRetryableError < ConductorError; end

  # Task in progress (not an error - for long-running tasks)
  class TaskInProgress
    attr_reader :callback_after_seconds, :output

    def initialize(callback_after: 60, output: {})
      @callback_after_seconds = callback_after
      @output = output
    end
  end
end
