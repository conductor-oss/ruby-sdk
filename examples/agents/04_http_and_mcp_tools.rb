# frozen_string_literal: true

# Port of python-sdk/examples/agents/04_http_and_mcp_tools.py.
# Run: bundle exec ruby -Ilib examples/agents/04_http_and_mcp_tools.rb
require 'conductor/agents'

module Example04HttpAndMcpTools
  include Conductor::Agents
  extend Conductor::Agents::Tools

  def format_report(title: String, body: String)
    { report: "=== #{title} ===\n#{body}\n#{'=' * (title.length + 8)}" }
  end
  tool :format_report, description: "Format a title and body into a structured report."

  def self.build(model: ENV.fetch('CONDUCTOR_AGENT_LLM_MODEL', 'openai/gpt-4o-mini'))
    reverse_api = Tool.http(
      "reverse_string",
      "http://localhost:3001/api/string/reverse",
      description: "Reverse a string using the HTTP API",
      method: "POST",
      headers: { "Authorization" => "Bearer ${HTTP_TEST_API_KEY}" },
      credentials: ["HTTP_TEST_API_KEY"],
      input_schema: { "type" => "object", "properties" => { "text" => { "type" => "string", "description" => "Text to reverse" } }, "required" => ["text"] }
    )
    mcp_test_tools = Tool.mcp(
      "http://localhost:3001/mcp",
      name: "mcp_test_tools",
      description: "Deterministic test tools via MCP — math, string, collection, encoding, hash, datetime, validation, and conversion operations.",
      headers: { "Authorization" => "Bearer ${MCP_TEST_API_KEY}" },
      credentials: ["MCP_TEST_API_KEY"]
    )
    agent = Agent.new(
      name: "http_tools_demo",
      model: model,
      tools: [self[:format_report], reverse_api, mcp_test_tools],
      instructions: "You can reverse strings and format reports. When asked to reverse a string, use reverse_string first, then format_report with the result."
    )
    agent
  end

  def self.run(runtime: Conductor::Agents.runtime, input: $stdin, output: $stdout)
    agent = build
    executions = []
    execution = runtime.call_async(agent, "Reverse the string 'hello world' and add 33 and 21 append the result to that string, then write a report with the result.")
    output.puts execution.result(timeout: 180)
    executions << execution
    executions
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    Example04HttpAndMcpTools.run
  ensure
    Conductor::Agents.shutdown
  end
end
