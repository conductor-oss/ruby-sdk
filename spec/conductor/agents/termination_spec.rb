# frozen_string_literal: true

require 'spec_helper'
require 'conductor/agents'

RSpec.describe Conductor::Agents::Termination do
  t = described_class

  it 'TextMention matches case-insensitively by default' do
    cond = t::TextMention.new('DONE')
    expect(cond.should_terminate('result' => 'all done').should_terminate).to be true
    expect(t::TextMention.new('DONE', case_sensitive: true).should_terminate(result: 'all done').should_terminate).to be false
    expect(cond.should_terminate('result' => 'working').should_terminate).to be false
    expect { t::TextMention.new('') }.to raise_error(Conductor::Agents::ConfigurationError)
  end

  it 'StopMessage needs an exact stripped match' do
    cond = t::StopMessage.new
    expect(cond.should_terminate('result' => " TERMINATE \n").should_terminate).to be true
    expect(cond.should_terminate('result' => 'TERMINATE now').should_terminate).to be false
  end

  it 'MaxMessage counts messages or falls back to iteration' do
    cond = t::MaxMessage.new(2)
    expect(cond.should_terminate('messages' => [1, 2]).should_terminate).to be true
    expect(cond.should_terminate('messages' => [], 'iteration' => 1).should_terminate).to be false
    expect(cond.should_terminate('iteration' => 5).reason).to include('5')
    expect { t::MaxMessage.new(0) }.to raise_error(Conductor::Agents::ConfigurationError)
  end

  it 'TokenUsage checks each configured limit' do
    cond = t::TokenUsage.new(max_total_tokens: 100)
    expect(cond.should_terminate('token_usage' => { 'total_tokens' => 100 }).should_terminate).to be true
    expect(cond.should_terminate('token_usage' => { 'totalTokens' => 10 }).should_terminate).to be false
    expect(cond.should_terminate({}).should_terminate).to be false
    expect { t::TokenUsage.new }.to raise_error(Conductor::Agents::ConfigurationError)
  end

  it 'combines with & and | and flattens same-type children' do
    a = t::TextMention.new('A')
    b = t::MaxMessage.new(3)
    c = t::StopMessage.new('X')
    both = a & b & c
    expect(both).to be_a(t::And)
    expect(both.conditions.size).to eq(3)
    expect(both.should_terminate('result' => 'A X', 'iteration' => 3).should_terminate).to be false
    expect(both.should_terminate('result' => 'A', 'iteration' => 3).should_terminate).to be false

    either = a | b | c
    expect(either).to be_a(t::Or)
    expect(either.conditions.size).to eq(3)
    expect(either.should_terminate('result' => 'X').reason).to include('X')
    expect(either.should_terminate('result' => 'nothing').should_terminate).to be false

    nested = c | (a & b)
    expect(nested.conditions.size).to eq(2)
    expect(nested.conditions.last).to be_a(t::And)
  end
end
