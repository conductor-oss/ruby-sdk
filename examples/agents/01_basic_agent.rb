# frozen_string_literal: true

# Port of python-sdk/examples/agents/01_basic_agent.py.
# Run: bundle exec ruby -Ilib examples/agents/01_basic_agent.rb
require 'conductor/agents'

module Example01BasicAgent
  include Conductor::Agents
  extend Conductor::Agents::Tools

  def self.build(model: ENV.fetch('CONDUCTOR_AGENT_LLM_MODEL', 'openai/gpt-4o-mini'))
    agent = Agent.new(
      name: "greeter",
      model: model,
      instructions: "You are a friendly assistant. Keep responses brief."
    )
    agent
  end

  def self.run(runtime: Conductor::Agents.runtime, input: $stdin, output: $stdout)
    agent = build
    executions = []
    execution = runtime.call_async(agent, "Say hello and tell me a fun fact about Python.")
    output.puts execution.result(timeout: 180)
    executions << execution
    executions
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    Example01BasicAgent.run
  ensure
    Conductor::Agents.shutdown
  end
end
