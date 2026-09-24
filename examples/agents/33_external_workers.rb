# frozen_string_literal: true

# Port of python-sdk/examples/agents/33_external_workers.py.
# Run: bundle exec ruby -Ilib examples/agents/33_external_workers.rb
require 'conductor/agents'

module Example33ExternalWorkers
  include Conductor::Agents
  extend Conductor::Agents::Tools

  def process_order(order_id: String, action: String)
    raise "External worker: implement this in a separate service"
  end
  tool :process_order, description: "Process a customer order. Actions: refund, cancel, update." , external: true

  def delete_account(user_id: String, reason: String)
    raise "External worker: implement this in a separate service"
  end
  tool :delete_account, description: "Permanently delete a user account. Requires manager approval." , external: true, approval_required: true

  def format_response(data: Hash)
    data.map { |key, value| "  #{key}: #{value}" }.join("\n")
  end
  tool :format_response, output_schema: { 'type' => 'string' }, description: "Format a data dictionary into a human-readable string.",
       input_schema: { 'type' => 'object', 'properties' => { 'data' => { 'type' => 'object', 'additionalProperties' => {} } }, 'required' => ['data'] }

  def get_customer(customer_id: String)
    raise "External worker: implement this in a separate service"
  end
  tool :get_customer, description: "Look up customer details from the CRM system." , external: true

  def check_inventory(product_id: String, warehouse: "default")
    raise "External worker: implement this in a separate service"
  end
  tool :check_inventory, description: "Check product availability in a warehouse.", external: true,
       input_schema: { 'type' => 'object', 'properties' => { 'product_id' => { 'type' => 'string' }, 'warehouse' => { 'type' => 'string' } },
                       'required' => ['product_id'] }

  def self.build(model: ENV.fetch('CONDUCTOR_AGENT_LLM_MODEL', 'openai/gpt-4o-mini'))
    support_agent = Agent.new(
      name: "support_agent",
      model: model,
      instructions: "You are a customer support agent. Use the available tools to look up customers, check inventory, process orders, and format responses for the customer.",
      tools: [self[:format_response], self[:get_customer], self[:check_inventory], self[:process_order]]
    )
    support_agent
  end

  def self.run(runtime: Conductor::Agents.runtime, input: $stdin, output: $stdout)
    support_agent = build
    executions = []
    execution = runtime.call_async(support_agent, "Customer C-1234 wants to cancel order ORD-5678. Look up the customer, check if we have the product in stock, and process the cancellation.")
    output.puts execution.result(timeout: 180)
    executions << execution
    executions
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    Example33ExternalWorkers.run
  ensure
    Conductor::Agents.shutdown
  end
end
