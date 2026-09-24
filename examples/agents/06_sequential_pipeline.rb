# frozen_string_literal: true

# Port of python-sdk/examples/agents/06_sequential_pipeline.py.
# Run: bundle exec ruby -Ilib examples/agents/06_sequential_pipeline.rb
require 'conductor/agents'

module Example06SequentialPipeline
  include Conductor::Agents
  extend Conductor::Agents::Tools

  def self.build(model: ENV.fetch('CONDUCTOR_AGENT_LLM_MODEL', 'openai/gpt-4o-mini'))
    researcher = Agent.new(
      name: "researcher",
      model: model,
      instructions: "You are a researcher. Given a topic, provide key facts and data points. Be thorough but concise. Output raw research findings."
    )
    writer = Agent.new(
      name: "writer",
      model: model,
      instructions: "You are a writer. Take research findings and write a clear, engaging article. Use headers and bullet points where appropriate."
    )
    editor = Agent.new(
      name: "editor",
      model: model,
      instructions: "You are an editor. Review the article for clarity, grammar, and tone. Make improvements and output the final polished version."
    )
    pipeline = researcher >> writer >> editor
    pipeline
  end

  def self.run(runtime: Conductor::Agents.runtime, input: $stdin, output: $stdout)
    pipeline = build
    executions = []
    execution = runtime.call_async(pipeline, "The impact of AI agents on software development in 2025")
    output.puts execution.result(timeout: 180)
    executions << execution
    executions
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    Example06SequentialPipeline.run
  ensure
    Conductor::Agents.shutdown
  end
end
