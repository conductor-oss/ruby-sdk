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
require_relative 'agents/tool_def'
require_relative 'agents/tools'
require_relative 'agents/guardrail'
require_relative 'agents/termination'
require_relative 'agents/handoff'
require_relative 'agents/callback_handler'
require_relative 'agents/memory'
require_relative 'agents/prompt_template'
require_relative 'agents/agent'
require_relative 'agents/config_serializer'

module Conductor
  # Ruby port of the Python SDK's conductor.ai.agents package
  module Agents
    include Tools
    include Secrets

    class << self
      # Tools and secrets are usable at the module level too (Conductor::Agents.tool ...)
      include Tools
      include Secrets
    end
  end
end
