# frozen_string_literal: true

# Port of python-sdk/examples/agents/02c_tool_retry_config.py.
# Run: bundle exec ruby -Ilib examples/agents/02c_tool_retry_config.rb
require 'conductor/agents'

module Example02cToolRetryConfig
  include Conductor::Agents
  extend Conductor::Agents::Tools

  def call_external_api(query: String)
    { result: "Data for: #{query}", source: "external_api" }
  end
  tool :call_external_api, description: "Call an unreliable external API that may need aggressive retries.", retry_policy: "exponential_backoff", retry_count: 5, retry_delay_seconds: 1

  def query_database(sql: String)
    { rows: [{ id: 1, value: sql }], count: 1 }
  end
  tool :query_database, description: "Run a database query with fixed-interval retries for transient connection issues." , retry_policy: "fixed", retry_count: 3, retry_delay_seconds: 5

  def process_data(data: String)
    { processed: data, status: "ok" }
  end
  tool :process_data, description: "Process data locally — light retries with linear backoff." , retry_policy: "linear_backoff", retry_count: 2, retry_delay_seconds: 2

  def self.build(model: ENV.fetch('CONDUCTOR_AGENT_LLM_MODEL', 'openai/gpt-4o-mini'))
    agent = Agent.new(
      name: "retry_config_demo",
      model: model,
      tools: [self[:call_external_api], self[:query_database], self[:process_data]],
      instructions: "You help users fetch and process data. Use the appropriate tool for each request."
    )
    agent
  end

  def self.run(runtime: Conductor::Agents.runtime, input: $stdin, output: $stdout)
    agent = build
    executions = []
    execution = runtime.call_async(agent, "Look up the latest Python release info from the API.")
    output.puts execution.result(timeout: 180)
    executions << execution
    executions
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    Example02cToolRetryConfig.run
  ensure
    Conductor::Agents.shutdown
  end
end
