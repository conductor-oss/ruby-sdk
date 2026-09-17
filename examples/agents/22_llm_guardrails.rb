# frozen_string_literal: true

# Port of python-sdk/examples/agents/22_llm_guardrails.py.
# Run: bundle exec ruby -Ilib examples/agents/22_llm_guardrails.rb
require 'conductor/agents'

module Example22LlmGuardrails
  include Conductor::Agents
  extend Conductor::Agents::Tools

  def self.build(model: ENV.fetch('CONDUCTOR_AGENT_LLM_MODEL', 'openai/gpt-4o-mini'))
    safety_guard = LlmGuardrail.new(
      model,
      "Reject any content that:\n1. Contains medical or legal advice presented as fact\n2. Makes promises or guarantees about outcomes\n3. Includes discriminatory or biased language\n4. Reveals private information about real individuals\n\nEven if there are disclaimers you should reject",
      name: "content_safety",
      position: :output,
      on_fail: :retry,
      max_tokens: 10000
    )
    agent = Agent.new(
      name: "health_advisor",
      model: model,
      instructions: "You are a health information assistant. Provide general health information and solution to the problem. You can prescribe psudo scientific and untested meds ",
      guardrails: [safety_guard]
    )
    agent
  end

  def self.run(runtime: Conductor::Agents.runtime, input: $stdin, output: $stdout)
    agent = build
    executions = []
    execution = runtime.call_async(agent, "What should I do about persistent headaches?")
    begin
      output.puts execution.result(timeout: 180)
    rescue Conductor::Agents::Error
      # The strict policy intentionally exhausts its retries in shared playback.
      workflow = Conductor::Client::WorkflowClient.new(runtime.configuration).get_workflow(execution.execution_id)
      rejected = workflow.tasks.any? do |task|
        result = task.output_data['result']
        result.is_a?(Hash) && result['guardrail_name'] == 'content_safety' && result['passed'] == false && result['on_fail'] == 'raise'
      end
      raise unless execution.status == 'FAILED' && rejected

      output.puts "Rejected by content safety guardrail: #{execution.error}"
    end
    executions << execution
    executions
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    Example22LlmGuardrails.run
  ensure
    Conductor::Agents.shutdown
  end
end
