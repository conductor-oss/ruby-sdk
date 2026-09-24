# frozen_string_literal: true

require 'spec_helper'
require 'conductor/agents'

RSpec.describe Conductor::Agents::Tool do
  describe '#initialize' do
    it 'applies the Python defaults' do
      td = described_class.new(name: 't')
      expect(td.description).to eq('')
      expect(td.input_schema).to eq({})
      expect(td.tool_type).to eq('worker')
      expect(td.approval_required).to be false
      expect(td.retry_count).to eq(2)
      expect(td.retry_delay_seconds).to eq(2)
      expect(td.retry_policy).to eq('linear_backoff')
      expect(td.retry_logic).to eq('LINEAR_BACKOFF')
      expect(td.credentials).to eq([])
      expect(td.server_side?).to be true
    end

    it 'rejects unknown tool types and retry policies' do
      expect { described_class.new(name: 't', tool_type: 'magic') }.to raise_error(Conductor::Agents::ConfigurationError)
      expect { described_class.new(name: 't', retry_policy: 'never') }.to raise_error(Conductor::Agents::ConfigurationError)
      expect { described_class.new(name: '') }.to raise_error(Conductor::Agents::ConfigurationError)
    end

    it 'is local only for worker/cli tools with a func' do
      expect(described_class.new(name: 't', func: -> {}).local?).to be true
      expect(described_class.new(name: 't', func: -> {}, tool_type: 'http').local?).to be false
      expect(described_class.new(name: 't').local?).to be false
    end
  end

  describe '#with_guardrails' do
    it 'returns a guarded copy and leaves the original untouched' do
      guard = Conductor::Agents::Guardrail.new(name: 'g') { true }
      original = described_class.new(name: 't', func: -> {})
      guarded = original.with_guardrails(guard)
      expect(guarded).not_to equal(original)
      expect(guarded.guardrails).to eq([guard])
      expect(guarded.name).to eq('t')
      expect(guarded.local?).to be true
      expect(original.guardrails).to eq([])
    end

    it 'replaces existing guardrails and flattens lists' do
      old = Conductor::Agents::Guardrail.new(name: 'old') { true }
      new1 = Conductor::Agents::Guardrail.new(name: 'new1') { true }
      new2 = Conductor::Agents::Guardrail.new(name: 'new2') { true }
      tool = described_class.new(name: 't', guardrails: [old])
      expect(tool.with_guardrails([new1, new2]).guardrails).to eq([new1, new2])
    end
  end

  describe '#call' do
    it 'builds a prefilled tool call' do
      call = described_class.new(name: 'get_weather').call(city: 'Lisbon')
      expect(call.to_h).to eq('toolName' => 'get_weather', 'arguments' => { 'city' => 'Lisbon' })
    end
  end

  describe '.http' do
    it 'serializes the Python config keys' do
      td = described_class.http('fetch', 'https://x.test/a', description: 'Fetch', method: 'post',
                                                             headers: { 'Authorization' => 'Bearer ${API_KEY}' }, credentials: ['API_KEY'])
      expect(td.tool_type).to eq('http')
      expect(td.config).to eq('url' => 'https://x.test/a', 'method' => 'POST',
                              'headers' => { 'Authorization' => 'Bearer ${API_KEY}' },
                              'accept' => ['application/json'], 'contentType' => 'application/json')
      expect(td.credentials).to eq(['API_KEY'])
      expect(td.input_schema).to eq('type' => 'object', 'properties' => {})
    end

    it 'rejects undeclared ${NAME} placeholders' do
      expect do
        described_class.http('fetch', 'https://x', headers: { 'X' => '${SECRET}' })
      end.to raise_error(Conductor::Agents::ConfigurationError, /SECRET/)
    end
  end

  describe '.mcp' do
    it 'defaults the name and carries server_url / max_tools' do
      td = described_class.mcp('http://mcp:3001/mcp', tool_names: %w[a b])
      expect(td.name).to eq('mcp_tools')
      expect(td.tool_type).to eq('mcp')
      expect(td.config).to eq('server_url' => 'http://mcp:3001/mcp', 'tool_names' => %w[a b], 'max_tools' => 64)
    end
  end

  describe '.human' do
    it 'uses a question schema by default' do
      td = described_class.human('ask_user', description: 'Ask the user.')
      expect(td.tool_type).to eq('human')
      expect(td.input_schema['required']).to eq(['question'])
    end
  end

  describe '.agent' do
    it 'wraps an agent with the request schema and retry config' do
      agent = Conductor::Agents::Agent.new(name: 'researcher', model: 'openai/gpt-4o')
      td = described_class.agent(agent, retry_count: 0, optional: false)
      expect(td.name).to eq('researcher')
      expect(td.description).to eq('Invoke the researcher agent')
      expect(td.tool_type).to eq('agent_tool')
      expect(td.config).to eq('agent' => agent, 'retryCount' => 0, 'optional' => false)
      expect(td.input_schema['required']).to eq(['request'])
    end
  end

  describe 'media, rag and message factories' do
    it 'set the task type in config' do
      expect(described_class.image('img', description: 'd', llm_provider: 'openai', model: 'dall-e-3').config['taskType']).to eq('GENERATE_IMAGE')
      expect(described_class.pdf.config).to eq('taskType' => 'GENERATE_PDF')
      idx = described_class.index('idx', description: 'd', vector_db: 'pinecone', index: 'docs',
                                         embedding_model_provider: 'openai', embedding_model: 'e', chunk_size: 100)
      expect(idx.config).to include('taskType' => 'LLM_INDEX_TEXT', 'chunkSize' => 100, 'namespace' => 'default_ns')
      search = described_class.search('s', description: 'd', vector_db: 'pinecone', index: 'docs',
                                           embedding_model_provider: 'openai', embedding_model: 'e')
      expect(search.config).to include('taskType' => 'LLM_SEARCH_INDEX', 'maxResults' => 5)
      expect(described_class.wait_for_message('w', description: 'd', blocking: false).config).to eq('batchSize' => 1, 'blocking' => false)
      expect(described_class.wait_for_message('w', description: 'd').config).to eq('batchSize' => 1)
    end
  end
end
