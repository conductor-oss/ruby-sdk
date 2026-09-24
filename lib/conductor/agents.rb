# frozen_string_literal: true

# Conductor::Agents - define agents in Ruby, run them on a Conductor server.
#
#   require 'conductor/agents'
#   include Conductor::Agents
#
#   tool def get_weather(city: String, units: 'metric')
#     { temp_c: 21.0, summary: "Sunny in #{city}" }
#   end
#
#   agent = Agent.new(name: 'weather', model: 'openai/gpt-4o', instructions: 'Answer weather questions.')
#   agent.add_tool :get_weather
#   puts agent.call_sync('Weather in Lisbon?')
require_relative '../conductor'
require_relative 'agents/errors'
require_relative 'agents/runtime/secrets'
require_relative 'agents/tool'
require_relative 'agents/tools'
require_relative 'agents/guardrail'
require_relative 'agents/termination'
require_relative 'agents/handoff'
require_relative 'agents/callback_handler'
require_relative 'agents/memory'
require_relative 'agents/prompt_template'
require_relative 'agents/agent'
require_relative 'agents/plans'
require_relative 'agents/config_serializer'
require_relative 'agents/runtime/agent_config'
require_relative 'agents/runtime/dispatch'
require_relative 'agents/runtime/system_workers'
require_relative 'agents/runtime/tool_registry'
require_relative 'agents/runtime/execution'
require_relative 'agents/runtime/approval_request'
require_relative 'agents/runtime/sse_client'
require_relative 'agents/runtime/status_poller'
require_relative 'agents/runtime/agent_runtime'

module Conductor
  # Ruby port of the Python SDK's conductor.ai.agents package
  module Agents
    include Tools
    include Secrets
    include Plans

    class << self
      # Tools and secrets are usable at the module level too (Conductor::Agents.tool ...)
      include Tools
      include Secrets
      include Plans

      # The default runtime used by Agent#call_sync / #call_async (built from the environment)
      # @return [AgentRuntime]
      def runtime
        @runtime ||= AgentRuntime.new
      end

      attr_writer :runtime

      # Replace the default runtime
      #   Conductor::Agents.configure(configuration: Conductor::Configuration.new(server_api_url: '...'))
      # @return [AgentRuntime]
      def configure(configuration: nil, agent_config: nil, logger: nil)
        @runtime&.shutdown
        @runtime = AgentRuntime.new(configuration: configuration, agent_config: agent_config, logger: logger)
      end

      # Stop the default runtime's workers and streams
      def shutdown
        @runtime&.shutdown
        @runtime = nil
      end
    end
  end
end
