# frozen_string_literal: true

require 'spec_helper'
require 'conductor/agents'

RSpec.describe Conductor::Agents::Handoff do
  h = described_class

  it 'accepts an Agent or a name as target' do
    agent = Conductor::Agents::Agent.new(name: 'filer', model: 'openai/gpt-4o')
    expect(h::OnTextMention.new(target: agent, text: 'x').target).to eq('filer')
    expect(h::OnTextMention.new(target: 'filer', text: 'x').target).to eq('filer')
    expect { h::OnTextMention.new(target: '', text: 'x') }.to raise_error(Conductor::Agents::ConfigurationError)
  end

  it 'OnTextMention matches case-insensitively' do
    cond = h::OnTextMention.new(target: 'filer', text: 'ACTIONABLE')
    expect(cond.should_handoff('result' => 'This is actionable')).to be true
    expect(cond.should_handoff(result: 'nope')).to be false
  end

  it 'OnToolResult matches the tool and optional substring' do
    cond = h::OnToolResult.new(target: 'refund', tool_name: 'check_order', result_contains: 'broken')
    expect(cond.should_handoff('tool_name' => 'check_order', 'tool_result' => 'item broken')).to be true
    expect(cond.should_handoff('tool_name' => 'check_order', 'tool_result' => 'fine')).to be false
    expect(cond.should_handoff('tool_name' => 'other')).to be false
    expect(h::OnToolResult.new(target: 'r', tool_name: 'x').should_handoff('tool_name' => 'x')).to be true
  end

  it 'OnCondition calls the block and swallows errors' do
    cond = h::OnCondition.new(target: 'summarizer') { |ctx| ctx['iteration'] > 5 }
    expect(cond.should_handoff('iteration' => 6)).to be true
    expect(cond.should_handoff('iteration' => 1)).to be false
    expect(cond.should_handoff({})).to be false
    expect { h::OnCondition.new(target: 's') }.to raise_error(Conductor::Agents::ConfigurationError)
  end
end
