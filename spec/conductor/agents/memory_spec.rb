# frozen_string_literal: true

require 'spec_helper'
require 'conductor/agents'

RSpec.describe Conductor::Agents::ConversationMemory do
  it 'records messages in the Conductor chat format' do
    m = described_class.new
    m.add_system_message('sys')
    m.add_user_message('hi')
    m.add_assistant_message('hello')
    m.add_tool_call('get_weather', { 'city' => 'Lisbon' })
    m.add_tool_result('get_weather', { temp: 21 })
    expect(m.messages).to eq([
                               { 'role' => 'system', 'message' => 'sys' },
                               { 'role' => 'user', 'message' => 'hi' },
                               { 'role' => 'assistant', 'message' => 'hello' },
                               { 'role' => 'tool_call', 'message' => '',
                                 'tool_calls' => [{ 'name' => 'get_weather', 'taskReferenceName' => 'get_weather_ref',
                                                    'input' => { 'city' => 'Lisbon' } }] },
                               { 'role' => 'tool', 'message' => '{:temp=>21}', 'toolCallId' => 'get_weather_ref',
                                 'taskReferenceName' => 'get_weather_ref' }
                             ])
  end

  it 'trims the oldest non-system messages first' do
    m = described_class.new(max_messages: 3)
    m.add_system_message('sys')
    m.add_user_message('one')
    m.add_assistant_message('two')
    m.add_user_message('three')
    expect(m.messages.map { |x| x['message'] }).to eq(%w[sys two three])
  end

  it 'deep copies in to_chat_messages and clears' do
    m = described_class.new(messages: [{ role: 'user', message: 'x' }])
    copy = m.to_chat_messages
    copy[0]['message'] = 'changed'
    expect(m.messages[0]['message']).to eq('x')
    m.clear
    expect(m).to be_empty
  end
end
