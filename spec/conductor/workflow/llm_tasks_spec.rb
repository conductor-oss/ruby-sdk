# frozen_string_literal: true

require 'spec_helper'

# === LLM Helper Classes ===
# These classes are used by the new DSL for LLM task construction

RSpec.describe Conductor::Workflow::Llm::Role do
  it 'defines all role constants' do
    expect(described_class::USER).to eq('user')
    expect(described_class::ASSISTANT).to eq('assistant')
    expect(described_class::SYSTEM).to eq('system')
    expect(described_class::TOOL_CALL).to eq('tool_call')
    expect(described_class::TOOL).to eq('tool')
  end
end

RSpec.describe Conductor::Workflow::Llm::ChatMessage do
  it 'creates a simple message' do
    msg = described_class.new(role: 'user', message: 'Hello')
    expect(msg.role).to eq('user')
    expect(msg.message).to eq('Hello')
  end

  it 'serializes to hash' do
    msg = described_class.new(role: 'system', message: 'You are helpful')
    hash = msg.to_h
    expect(hash).to eq({ 'role' => 'system', 'message' => 'You are helpful' })
  end

  it 'includes media when present' do
    msg = described_class.new(role: 'user', message: 'Describe this', media: ['https://img.example.com/1.png'])
    hash = msg.to_h
    expect(hash['media']).to eq(['https://img.example.com/1.png'])
  end

  it 'includes mimeType when present' do
    msg = described_class.new(role: 'user', message: 'See image', mime_type: 'image/png')
    hash = msg.to_h
    expect(hash['mimeType']).to eq('image/png')
  end

  it 'omits empty media array' do
    msg = described_class.new(role: 'user', message: 'Hi', media: [])
    hash = msg.to_h
    expect(hash).not_to have_key('media')
  end

  it 'includes tool_calls when present' do
    tc = Conductor::Workflow::Llm::ToolCall.new(name: 'search')
    msg = described_class.new(role: 'assistant', message: '', tool_calls: [tc])
    hash = msg.to_h
    expect(hash['toolCalls']).to be_an(Array)
    expect(hash['toolCalls'].first['name']).to eq('search')
  end
end

RSpec.describe Conductor::Workflow::Llm::ToolCall do
  it 'creates with defaults' do
    tc = described_class.new(name: 'get_weather')
    expect(tc.name).to eq('get_weather')
    expect(tc.type).to eq('SIMPLE')
  end

  it 'serializes to hash' do
    tc = described_class.new(
      name: 'search', task_reference_name: 'search_ref',
      integration_names: { 'google' => 'search_api' },
      input_parameters: { 'query' => 'hello' }
    )
    hash = tc.to_h
    expect(hash['name']).to eq('search')
    expect(hash['type']).to eq('SIMPLE')
    expect(hash['taskReferenceName']).to eq('search_ref')
    expect(hash['integrationNames']).to eq({ 'google' => 'search_api' })
    expect(hash['inputParameters']).to eq({ 'query' => 'hello' })
  end
end

RSpec.describe Conductor::Workflow::Llm::ToolSpec do
  it 'creates with defaults' do
    spec = described_class.new(name: 'get_weather')
    expect(spec.name).to eq('get_weather')
    expect(spec.type).to eq('SIMPLE')
  end

  it 'serializes to hash with all fields' do
    spec = described_class.new(
      name: 'search', description: 'Search the web',
      input_schema: { 'type' => 'object', 'properties' => { 'q' => { 'type' => 'string' } } }
    )
    hash = spec.to_h
    expect(hash['name']).to eq('search')
    expect(hash['description']).to eq('Search the web')
    expect(hash['inputSchema']).to have_key('properties')
  end
end

RSpec.describe Conductor::Workflow::Llm::EmbeddingModel do
  it 'stores provider and model' do
    em = described_class.new(provider: 'openai', model: 'text-embedding-ada-002')
    expect(em.provider).to eq('openai')
    expect(em.model).to eq('text-embedding-ada-002')
  end
end
