#!/usr/bin/env ruby
# frozen_string_literal: true

# Tools: an agent with one Ruby method as a tool.
#
#   export CONDUCTOR_SERVER_URL=http://localhost:8080/api
#   bundle exec ruby examples/agents/weather.rb
#
# The model string names a server-side integration ("openai" here) and a model; the SDK
# never sees the provider key.
require_relative '../../lib/conductor/agents'
include Conductor::Agents

tool def get_weather(city: String, units: 'metric')
  { temp_c: 21.0, summary: "Sunny in #{city}" }
end
describe :get_weather, 'Get the current weather for a city.'

agent = Agent.new(
  name: 'weather',
  model: ENV.fetch('CONDUCTOR_AGENT_LLM_MODEL', 'openai/gpt-4o-mini'),
  instructions: 'Answer weather questions.'
)
agent.add_tool :get_weather

puts agent.call_sync('Weather in Lisbon?')
Conductor::Agents.shutdown
