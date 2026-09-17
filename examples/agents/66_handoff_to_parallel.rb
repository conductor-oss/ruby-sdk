# frozen_string_literal: true

# Port of python-sdk/examples/agents/66_handoff_to_parallel.py.
# Run: bundle exec ruby -Ilib examples/agents/66_handoff_to_parallel.rb
require 'conductor/agents'

module Example66HandoffToParallel
  include Conductor::Agents
  extend Conductor::Agents::Tools

  def self.build(model: ENV.fetch('CONDUCTOR_AGENT_LLM_MODEL', 'openai/gpt-4o-mini'))
    quick_check = Agent.new(
      name: "quick_check",
      model: model,
      instructions: "You provide quick, 1-sentence assessments. Be brief and direct."
    )
    market_analyst = Agent.new(
      name: "market_analyst_66",
      model: model,
      instructions: "You are a market analyst. Analyze the market opportunity: size, growth rate, key players. 3-4 bullet points."
    )
    risk_analyst = Agent.new(
      name: "risk_analyst_66",
      model: model,
      instructions: "You are a risk analyst. Identify the top 3 risks: regulatory, technical, and competitive. 3-4 bullet points."
    )
    deep_analysis = Agent.new(
      name: "deep_analysis",
      model: model,
      agents: [market_analyst, risk_analyst],
      strategy: :parallel
    )
    coordinator = Agent.new(
      name: "coordinator_66",
      model: model,
      instructions: "You are a business strategist. Route requests to the right team:\n- quick_check for simple yes/no questions or quick assessments\n- deep_analysis for comprehensive analysis requiring multiple perspectives",
      agents: [quick_check, deep_analysis],
      strategy: :handoff
    )
    coordinator
  end

  def self.run(runtime: Conductor::Agents.runtime, input: $stdin, output: $stdout)
    coordinator = build
    executions = []
    execution = runtime.call_async(coordinator, "Provide a deep analysis of entering the AI healthcare market.")
    output.puts execution.result(timeout: 180)
    executions << execution
    execution = runtime.call_async(coordinator, "Is the mobile app market still growing?")
    output.puts execution.result(timeout: 180)
    executions << execution
    executions
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    Example66HandoffToParallel.run
  ensure
    Conductor::Agents.shutdown
  end
end
