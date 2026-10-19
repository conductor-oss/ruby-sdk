# frozen_string_literal: true

# Port of Python PR #511: a normal chat agent calls a server-side decision tool.
# The tool compiles to a branchless decision SWITCH and needs no Ruby worker.
# Run: CONDUCTOR_SERVER_URL=http://localhost:8085/api CONDUCTOR_DECISION_PROVIDER=openrouter \
#   bundle exec ruby -Ilib examples/agents/decision_tool.rb
require 'conductor/agents'

module ExampleDecisionTool
  include Conductor::Agents

  def self.build(model: ENV.fetch('CONDUCTOR_AGENT_LLM_MODEL', 'openai/gpt-4o-mini'))
    config = {
      'model' => 'jev-1.13',
      'questions' => {
        'department' => {
          'type' => 'choice', 'instructions' => 'Choose the correct support department.',
          'choices' => { 'billing' => 'Payments and invoices', 'technical' => 'Product errors and troubleshooting' }
        }
      }
    }
    config['provider'] = ENV['CONDUCTOR_DECISION_PROVIDER'] if ENV.key?('CONDUCTOR_DECISION_PROVIDER')
    classify = Tool.new(
      name: 'classify_request_ruby', description: 'Classify the customer request before answering.', tool_type: ToolType::DECISION,
      input_schema: { 'type' => 'object', 'properties' => { 'state' => { 'type' => 'string' } }, 'required' => ['state'] },
      config: config
    )
    Agent.new(name: 'decision_tool_support_ruby', model: model,
              instructions: 'Call classify_request_ruby before answering the customer.', tools: [classify])
  end

  def self.run(runtime: Conductor::Agents.runtime)
    execution = runtime.call_async(build, 'I was charged twice on my latest invoice.')
    puts "Execution: #{execution.execution_id}"
    puts execution.result(timeout: 120)
    execution
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    ExampleDecisionTool.run
  ensure
    Conductor::Agents.shutdown
  end
end
