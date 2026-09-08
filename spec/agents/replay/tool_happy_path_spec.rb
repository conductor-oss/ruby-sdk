# frozen_string_literal: true

require_relative '../agents_helper'
require_relative '../support/weather_tools'

# Replays conductor-mocks/mocks/agent/tool_happy_path: the LLM calls get_weather("Lisbon"),
# the tool runs in this process, and the agent answers from the result.
RSpec.describe 'weather agent', mocks: 'agent/tool_happy_path' do
  let(:agent) do
    agent = Conductor::Agents::Agent.new(name: 'weather', model: 'openai/gpt-4o-mini',
                                         instructions: 'Answer weather questions.')
    agent.add_tool WeatherTools[:get_weather]
    agent
  end

  it 'answers with the tool' do
    execution = agent.call_async('Weather in Lisbon?')
    answer = execution.result(timeout: 60)

    expect(answer).to include('Lisbon')
    expect(execution.finish_reason).to eq(:stop)
    expect(execution.tool_calls.map(&:name)).to eq(['get_weather'])
    expect(execution.tool_calls.first.arguments).to eq('city' => 'Lisbon', 'units' => 'metric')
    expect(execution.tool_calls.first.result).to eq('temp_c' => 21.0, 'summary' => 'Sunny in Lisbon')
    expect(execution.token_usage.total_tokens).to eq(246)
    expect(Conductor::Agents.runtime.running_workers).to eq(['get_weather'])
  end
end
