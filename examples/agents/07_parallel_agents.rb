# frozen_string_literal: true

# Port of python-sdk/examples/agents/07_parallel_agents.py.
# Run: bundle exec ruby -Ilib examples/agents/07_parallel_agents.rb
require 'conductor/agents'

module Example07ParallelAgents
  include Conductor::Agents
  extend Conductor::Agents::Tools

  def self.build(model: ENV.fetch('CONDUCTOR_AGENT_LLM_MODEL', 'openai/gpt-4o-mini'))
    market_analyst = Agent.new(
      name: "market_analyst",
      model: model,
      instructions: "You are a market analyst. Analyze the given topic from a market perspective: market size, growth trends, key players, and opportunities."
    )
    risk_analyst = Agent.new(
      name: "risk_analyst",
      model: model,
      instructions: "You are a risk analyst. Analyze the given topic for risks: regulatory risks, technical risks, competitive threats, and mitigation strategies."
    )
    compliance_checker = Agent.new(
      name: "compliance",
      model: model,
      instructions: "You are a compliance specialist. Check the given topic for compliance considerations: data privacy, regulatory requirements, and industry standards."
    )
    analysis = Agent.new(
      name: "analysis",
      model: model,
      agents: [market_analyst, risk_analyst, compliance_checker],
      strategy: :parallel
    )
    analysis
  end

  def self.run(runtime: Conductor::Agents.runtime, input: $stdin, output: $stdout)
    analysis = build
    executions = []
    execution = runtime.call_async(analysis, "Launching an AI-powered healthcare diagnostic tool in the US market")
    output.puts execution.result(timeout: 180)
    executions << execution
    executions
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    Example07ParallelAgents.run
  ensure
    Conductor::Agents.shutdown
  end
end
