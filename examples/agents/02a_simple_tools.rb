# frozen_string_literal: true

# Port of python-sdk/examples/agents/02a_simple_tools.py.
# Run: bundle exec ruby -Ilib examples/agents/02a_simple_tools.rb
require 'conductor/agents'

module Example02aSimpleTools
  include Conductor::Agents
  extend Conductor::Agents::Tools

  def get_weather(city: String)
    { city: city, temp_f: 72, condition: "Sunny" }
  end
  tool :get_weather, description: "Get the current weather for a city."

  def get_stock_price(symbol: String)
    { symbol: symbol, price: 182.50, change: "+1.2%" }
  end
  tool :get_stock_price, description: "Get the current stock price for a ticker symbol."

  def self.build(model: ENV.fetch('CONDUCTOR_AGENT_LLM_MODEL', 'openai/gpt-4o-mini'))
    agent = Agent.new(
      name: "weather_stock_agent",
      model: model,
      tools: [self[:get_weather], self[:get_stock_price]],
      instructions: "You are a helpful assistant. Use tools to answer questions."
    )
    agent
  end

  def self.run(runtime: Conductor::Agents.runtime, input: $stdin, output: $stdout)
    agent = build
    executions = []
    execution = runtime.call_async(agent, "What's the weather like in San Francisco?")
    output.puts execution.result(timeout: 180)
    executions << execution
    executions
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    Example02aSimpleTools.run
  ensure
    Conductor::Agents.shutdown
  end
end
