# frozen_string_literal: true

# Port of python-sdk/examples/agents/05_handoffs.py.
# Run: bundle exec ruby -Ilib examples/agents/05_handoffs.rb
require 'conductor/agents'

module Example05Handoffs
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

  def get_pricing(product: String)
    { product: product, price: 99.99, discount: "10% off" }
  end
  tool :get_pricing, description: "Get pricing information for a product."

  def self.build(model: ENV.fetch('CONDUCTOR_AGENT_LLM_MODEL', 'openai/gpt-4o-mini'))
    billing_agent = Agent.new(
      name: "billing",
      model: model,
      instructions: "You handle billing questions: balances, payments, invoices.",
      tools: [self[:check_balance]]
    )
    technical_agent = Agent.new(
      name: "technical",
      model: model,
      instructions: "You handle technical questions: order status, shipping, returns.",
      tools: [self[:lookup_order]]
    )
    sales_agent = Agent.new(
      name: "sales",
      model: model,
      instructions: "You handle sales questions: pricing, products, promotions.",
      tools: [self[:get_pricing]]
    )
    support = Agent.new(
      name: "support",
      model: model,
      instructions: "Route customer requests to the right specialist: billing, technical, or sales.",
      agents: [billing_agent, technical_agent, sales_agent],
      strategy: :handoff
    )
    support
  end

  def self.run(runtime: Conductor::Agents.runtime, input: $stdin, output: $stdout)
    support = build
    executions = []
    execution = runtime.call_async(support, "What's the balance on account ACC-123?")
    output.puts execution.result(timeout: 180)
    executions << execution
    executions
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    Example05Handoffs.run
  ensure
    Conductor::Agents.shutdown
  end
end
