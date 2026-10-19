# frozen_string_literal: true

# Port of Python PR #511: a decision Tool selects one of two chat agents.
# The selector compiles to a synchronous server-side SWITCH; no Ruby worker is needed.
# Run without --run to print the configuration without contacting the server.
# Run: CONDUCTOR_SERVER_URL=http://localhost:8085/api CONDUCTOR_DECISION_PROVIDER=openrouter \
#   bundle exec ruby -Ilib examples/agents/decision_router.rb --run
require 'conductor/agents'

module ExampleDecisionRouter
  include Conductor::Agents

  def self.build(model: ENV.fetch('CONDUCTOR_AGENT_LLM_MODEL', 'openai/gpt-4o-mini'))
    billing = Agent.new(name: 'billing_ruby', model: model,
                        instructions: 'Help the customer with billing and invoice questions.')
    technical = Agent.new(name: 'technical_ruby', model: model,
                          instructions: 'Help the customer troubleshoot product issues.')
    config = {
      'model' => 'jev-1.13',
      'questions' => {
        'agent' => {
          'type' => 'choice', 'instructions' => 'Choose the right support team.',
          'choices' => { 'billing_ruby' => 'Payments and invoices', 'technical_ruby' => 'Product errors and troubleshooting' }
        }
      }
    }
    config['provider'] = ENV['CONDUCTOR_DECISION_PROVIDER'] if ENV.key?('CONDUCTOR_DECISION_PROVIDER')
    selector = Tool.new(name: 'support_selector_ruby', tool_type: ToolType::DECISION,
                        description: 'Choose the support agent that should handle the request.', config: config)
    Agent.new(name: 'decision_support_router_ruby', strategy: Strategy::ROUTER, router: selector,
              agents: [billing, technical], max_turns: 1, synthesize: false)
  end

  def self.run(runtime: Conductor::Agents.runtime)
    agent = build
    runtime.deploy(agent)
    execution = runtime.call_async(agent, 'The customer reports a duplicate charge on the latest invoice.')
    puts "Execution: #{execution.execution_id}"
    puts execution.result(timeout: 120)
    execution
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.delete('--run')
    begin
      ExampleDecisionRouter.run
    ensure
      Conductor::Agents.shutdown
    end
  else
    puts JSON.pretty_generate(Conductor::Agents::ConfigSerializer.serialize(ExampleDecisionRouter.build))
  end
end
