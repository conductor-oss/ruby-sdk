# frozen_string_literal: true

# Port of python-sdk/examples/agents/09_human_in_the_loop.py.
# Run: bundle exec ruby -Ilib examples/agents/09_human_in_the_loop.rb
require 'conductor/agents'

module Example09HumanInTheLoop
  include Conductor::Agents
  extend Conductor::Agents::Tools

  def check_balance(account_id: String)
    { account_id: account_id, balance: 15000.00 }
  end
  tool :check_balance, description: "Check the balance of an account."

  def transfer_funds(from_acct: String, to_acct: String, amount: Float)
    { status: "completed", from: from_acct, to: to_acct, amount: amount }
  end
  tool :transfer_funds, description: "Request a funds transfer; runtime pauses for human approval before execution." , approval_required: true

  def self.build(model: ENV.fetch('CONDUCTOR_AGENT_LLM_MODEL', 'openai/gpt-4o-mini'))
    agent = Agent.new(
      name: "banker",
      model: model,
      tools: [self[:check_balance], self[:transfer_funds]],
      instructions: "You are a banking assistant. Use check_balance for balance inquiries. When asked to transfer money, first check the balance, then call transfer_funds to request the transfer. The runtime will pause for human approval before the transfer executes."
    )
    agent
  end

  def self.run(runtime: Conductor::Agents.runtime, input: $stdin, output: $stdout)
    agent = build
    agent.on_approval do |request|
      output.puts "Approval requested: #{request.tool_calls}"
      response = {}
      request.response_schema.fetch('properties').each do |field, schema|
        output.print "#{schema['description'] || schema['title'] || field}: "
        answer = input.gets
        raise EOFError, "No response supplied for #{field}" unless answer

        response[field] = schema['type'] == 'boolean' ? %w[y yes].include?(answer.strip.downcase) : answer.strip
      end
      request.respond(response)
    end
    executions = []
    execution = runtime.call_async(agent, "Transfer $500 from ACC-789 to ACC-456. Check the balance first.")
    output.puts execution.result(timeout: 180)
    executions << execution
    executions
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    Example09HumanInTheLoop.run
  ensure
    Conductor::Agents.shutdown
  end
end
