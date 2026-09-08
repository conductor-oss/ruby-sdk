# frozen_string_literal: true

require_relative '../exceptions'

module Conductor
  module Agents
    # Base class for agent definition and runtime errors
    class Error < ConductorError; end

    # Invalid agent/tool definition (bad name, missing model, positional tool args, ...)
    class ConfigurationError < Error; end

    # secret('X') was called but X is neither on the task's runtimeMetadata nor in ENV
    class CredentialNotFoundError < Error; end

    # A tool returned something that cannot be serialized to JSON
    class ToolSerializationError < Error; end

    # The SSE stream could not be opened (non-200, connection failure, heartbeat-only)
    class SseUnavailableError < Error; end

    # Server-side agent API errors are the transport-level classes
    AgentApiError = Conductor::AgentApiError
    AgentNotFoundError = Conductor::AgentNotFoundError
  end
end
