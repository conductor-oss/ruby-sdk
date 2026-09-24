# frozen_string_literal: true

# Port of python-sdk/examples/agents/21_regex_guardrails.py.
# Run: bundle exec ruby -Ilib examples/agents/21_regex_guardrails.rb
require 'conductor/agents'

module Example21RegexGuardrails
  include Conductor::Agents
  extend Conductor::Agents::Tools

  def get_user_profile(user_id: String)
    { name: "Alice Johnson", email: "alice.johnson@example.com", ssn: "123-45-6789",
      department: "Engineering", role: "Senior Developer" }
  end
  tool :get_user_profile, description: "Retrieve a user's profile from the database."

  def self.build(model: ENV.fetch('CONDUCTOR_AGENT_LLM_MODEL', 'openai/gpt-4o-mini'))
    no_emails = RegexGuardrail.new(
      ["[\\w.+-]+@[\\w-]+\\.[\\w.-]+"],
      mode: "block",
      name: "no_email_addresses",
      message: "Response must not contain email addresses. Redact them.",
      position: :output,
      on_fail: :retry
    )
    no_ssn = RegexGuardrail.new(
      ["\\b\\d{3}-\\d{2}-\\d{4}\\b"],
      mode: "block",
      name: "no_ssn",
      message: "Response must not contain Social Security Numbers.",
      position: :output,
      on_fail: :raise
    )
    agent = Agent.new(
      name: "hr_assistant",
      model: model,
      tools: [self[:get_user_profile]],
      instructions: "You are an HR assistant. When asked about employees, look up their profile and share ALL the details you find.",
      guardrails: [no_emails, no_ssn]
    )
    clean_agent = Agent.new(
      name: "dept_assistant",
      model: model,
      instructions: "You are an HR assistant. Answer questions about departments.",
      guardrails: [no_emails, no_ssn]
    )
    [agent, clean_agent]
  end

  def self.run(runtime: Conductor::Agents.runtime, input: $stdin, output: $stdout)
    agent, clean_agent = build
    executions = []
    execution = runtime.call_async(agent, "Tell me everything about user U-001.")
    output.puts execution.result(timeout: 180)
    executions << execution
    execution = runtime.call_async(clean_agent, "What departments exist at the company?")
    output.puts execution.result(timeout: 180)
    executions << execution
    executions
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    Example21RegexGuardrails.run
  ensure
    Conductor::Agents.shutdown
  end
end
