# frozen_string_literal: true

# Port of python-sdk/examples/agents/17_swarm_orchestration.py.
# Run: bundle exec ruby -Ilib examples/agents/17_swarm_orchestration.rb
require 'conductor/agents'

module Example17SwarmOrchestration
  include Conductor::Agents
  extend Conductor::Agents::Tools

  def self.build(model: ENV.fetch('CONDUCTOR_AGENT_LLM_MODEL', 'openai/gpt-4o-mini'))
    refund_agent = Agent.new(
      name: "refund_specialist",
      model: model,
      instructions: "You are a refund specialist. Process the customer's refund request. Check eligibility, confirm the refund amount, and let them know the timeline. Be empathetic and clear. Do NOT ask follow-up questions — just process the refund based on what the customer told you."
    )
    tech_agent = Agent.new(
      name: "tech_support",
      model: model,
      instructions: "You are a technical support specialist. Diagnose the customer's technical issue and provide clear troubleshooting steps."
    )
    support = Agent.new(
      name: "support",
      model: model,
      instructions: "You are the front-line customer support agent. Triage customer requests. If the customer needs a refund, transfer to the refund specialist. If they have a technical issue, transfer to tech support. Use the transfer tools available to you to hand off the conversation.",
      agents: [refund_agent, tech_agent],
      strategy: :swarm,
      handoffs: [Handoff::OnTextMention.new(
      text: "refund",
      target: "refund_specialist"
    ), Handoff::OnTextMention.new(
      text: "technical",
      target: "tech_support"
    )],
      max_turns: 3
    )
    support
  end

  def self.run(runtime: Conductor::Agents.runtime, input: $stdin, output: $stdout)
    support = build
    executions = []
    execution = runtime.call_async(support, "I bought a product last week and it arrived damaged. I want my money back.")
    output.puts execution.result(timeout: 180)
    executions << execution
    executions
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    Example17SwarmOrchestration.run
  ensure
    Conductor::Agents.shutdown
  end
end
