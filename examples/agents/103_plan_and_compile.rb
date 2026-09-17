# frozen_string_literal: true

# Port of python-sdk/examples/agents/103_plan_and_compile.py.
# Run: bundle exec ruby -Ilib examples/agents/103_plan_and_compile.rb
require 'conductor/agents'

module Example103PlanAndCompile
  include Conductor::Agents
  extend Conductor::Agents::Tools

  def factorial(n: Integer)
    return "ERROR: n must be in [0, 20], got #{n}" unless (0..20).cover?(n)

    (1..n).reduce(1, :*).to_s
  end
  tool :factorial, output_schema: { 'type' => 'string' }, description: "Compute n! and return it as a string.\n\nArgs:\n    n: Non-negative integer. Capped at 20 to keep things sane."

  def write_summary(text: String)
    text
  end
  tool :write_summary, output_schema: { 'type' => 'string' }, description: "Persist a short summary string. Returns it back for the validator."

  def check_summary(text: String, min_chars: Integer)
    JSON.generate(passed: text.length >= min_chars, length: text.length, min_chars: min_chars)
  end
  tool :check_summary, output_schema: { 'type' => 'string' }, description: "Return JSON ``{passed, length, min_chars}`` for the validator.\n\nArgs:\n    text: The summary to check.\n    min_chars: Minimum acceptable length in characters."

  def self.build(model: ENV.fetch('CONDUCTOR_AGENT_LLM_MODEL', 'openai/gpt-4o-mini'))
    planner_instructions = "You are a math-explainer planner. Plan a workflow that:\n\n1. Computes factorials of 1, 2, 3, 4, 5 in PARALLEL using ``factorial`` (static args).\n2. Writes a short prose summary about factorial growth using ``write_summary``\n   (use a ``generate`` block — the LLM produces the ``text`` arg at run time).\n3. Validates the summary is at least 30 characters via ``check_summary``,\n   with ``success_condition: \"$.passed === true\"``.\n"
    harness = Conductor::Agents.plan_execute(
      name: "plan_and_compile_demo",
      tools: [self[:factorial], self[:write_summary], self[:check_summary]],
      planner_instructions: planner_instructions,
      fallback_instructions: "The plan failed. Use the available tools to recover.",
      fallback_max_turns: 4,
      model: model
    )
    harness
  end

  def self.run(runtime: Conductor::Agents.runtime, input: $stdin, output: $stdout, topic: 'factorials')
    harness = build
    executions = []
    execution = runtime.call_async(harness, "Topic: #{topic}")
    output.puts execution.result(timeout: 180)
    compiled = find_plan_and_compile_output(runtime, execution.execution_id)
    raise 'No PLAN_AND_COMPILE task found in the workflow tree' unless compiled
    raise "Plan compilation failed: #{compiled['error']}" if compiled['error']

    output.puts "Compiled workflow: #{compiled['workflowName']}"
    output.puts "Stats: #{compiled['stats']}"
    Array(compiled.dig('workflowDef', 'tasks')).each do |task|
      output.puts "#{task['type']}: #{task['taskReferenceName']}"
    end
    executions << execution
    executions
  end

  def self.find_plan_and_compile_output(runtime, execution_id)
    client = Conductor::Client::WorkflowClient.new(runtime.configuration)
    pending = [execution_id]
    visited = []
    until pending.empty?
      id = pending.pop
      next if visited.include?(id)

      visited << id
      workflow = client.get_workflow(id)
      workflow.tasks.each do |task|
        return task.output_data if task.task_type == 'PLAN_AND_COMPILE'

        pending << task.sub_workflow_id if task.sub_workflow_id
      end
    end
    nil
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    Example103PlanAndCompile.run(topic: ARGV.empty? ? 'factorials' : ARGV.join(' '))
  ensure
    Conductor::Agents.shutdown
  end
end
