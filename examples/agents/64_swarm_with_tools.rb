# frozen_string_literal: true

# Port of python-sdk/examples/agents/64_swarm_with_tools.py.
# Run: bundle exec ruby -Ilib examples/agents/64_swarm_with_tools.rb
require 'conductor/agents'

module Example64SwarmWithTools
  include Conductor::Agents
  extend Conductor::Agents::Tools

  def check_balance(account_id: String)
    { account_id: account_id, balance: 5432.10, currency: "USD" }
  end
  tool :check_balance, description: "Check the balance of a bank account."

  def lookup_order(order_id: String)
    { order_id: order_id, status: "shipped", eta: "2 days" }
  end
  tool :lookup_order, description: "Look up the status of an order."

  def self.build(model: ENV.fetch('CONDUCTOR_AGENT_LLM_MODEL', 'openai/gpt-4o-mini'))
    billing_specialist = Agent.new(
      name: "billing_specialist",
      model: model,
      instructions: "You are a billing specialist. Use the check_balance tool to look up account balances. Include the balance amount in your response.",
      tools: [self[:check_balance]]
    )
    order_specialist = Agent.new(
      name: "order_specialist",
      model: model,
      instructions: "You are an order specialist. Use the lookup_order tool to check order status. Include the shipping status and ETA in your response.",
      tools: [self[:lookup_order]]
    )
    support = Agent.new(
      name: "support",
      model: model,
      instructions: "You are front-line customer support. Triage customer requests. Transfer to billing_specialist for account/payment questions, order_specialist for shipping/order questions.",
      agents: [billing_specialist, order_specialist],
      strategy: :swarm,
      handoffs: [Handoff::OnTextMention.new(
      text: "billing",
      target: "billing_specialist"
    ), Handoff::OnTextMention.new(
      text: "order",
      target: "order_specialist"
    )],
      max_turns: 3
    )
    support
  end

  def self.run(runtime: Conductor::Agents.runtime, input: $stdin, output: $stdout)
    support = build
    executions = []
    execution = runtime.call_async(support, "What's the balance on account ACC-456?")
    output.puts execution.result(timeout: 180)
    executions << execution
    execution = runtime.call_async(support, "Where is my order ORD-789?")
    output.puts execution.result(timeout: 180)
    executions << execution
    executions
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    Example64SwarmWithTools.run
  ensure
    Conductor::Agents.shutdown
  end
end
