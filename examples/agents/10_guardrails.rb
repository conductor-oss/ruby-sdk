# frozen_string_literal: true

# Port of python-sdk/examples/agents/10_guardrails.py.
# Run: bundle exec ruby -Ilib examples/agents/10_guardrails.rb
require 'conductor/agents'

module Example10Guardrails
  include Conductor::Agents
  extend Conductor::Agents::Tools

  def get_order_status(order_id: String)
    { order_id: order_id, status: "shipped", tracking: "1Z999AA10123456784", estimated_delivery: "2026-02-22" }
  end
  tool :get_order_status, description: "Look up the current status of an order."

  def get_customer_info(customer_id: String)
    { customer_id: customer_id, name: "Alice Johnson", email: "alice@example.com",
      card_on_file: "4532-0150-1234-5678", membership: "gold" }
  end
  tool :get_customer_info, description: "Retrieve customer details including payment info on file."

  def self.pii_guardrail
    Guardrail.new(name: "no_pii", position: :output, on_fail: :retry) do |content|
      pii = /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b|\b\d{3}-\d{2}-\d{4}\b/
      if pii.match?(content)
        GuardrailResult.new(passed: false, message: "Your response contains PII (credit card or SSN). Redact all card numbers and SSNs before responding.")
      else
        GuardrailResult.new(passed: true)
      end
    end
  end

  def self.build(model: ENV.fetch('CONDUCTOR_AGENT_LLM_MODEL', 'openai/gpt-4o-mini'))
    no_pii = pii_guardrail
    agent = Agent.new(
      name: "support_agent",
      model: model,
      tools: [self[:get_order_status], self[:get_customer_info]],
      instructions: "You are a customer support assistant. Use the available tools to answer questions about orders and customers. Always include all details from the tool results in your response.",
      guardrails: [no_pii]
    )
    agent
  end

  def self.run(runtime: Conductor::Agents.runtime, input: $stdin, output: $stdout)
    agent = build
    executions = []
    execution = runtime.call_async(agent, "I need a full summary: What's the status of order ORD-42, and what's the profile for customer CUST-7?")
    output.puts execution.result(timeout: 180)
    executions << execution
    executions
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    Example10Guardrails.run
  ensure
    Conductor::Agents.shutdown
  end
end
