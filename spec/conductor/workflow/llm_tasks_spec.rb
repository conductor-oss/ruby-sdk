# frozen_string_literal: true

require 'spec_helper'

# === Helper Classes ===

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

# === LLM Task Classes ===

RSpec.describe Conductor::Workflow::Llm::LlmChatCompleteTask do
  it 'creates with required parameters' do
    task = described_class.new('chat_ref', 'openai', 'gpt-4')
    expect(task.task_reference_name).to eq('chat_ref')
    expect(task.task_type).to eq('LLM_CHAT_COMPLETE')
    expect(task.name).to eq('llm_chat_complete')
    expect(task.input_parameters['llmProvider']).to eq('openai')
    expect(task.input_parameters['model']).to eq('gpt-4')
  end

  it 'includes messages when provided' do
    msgs = [
      Conductor::Workflow::Llm::ChatMessage.new(role: 'system', message: 'Be helpful'),
      Conductor::Workflow::Llm::ChatMessage.new(role: 'user', message: 'Hi')
    ]
    task = described_class.new('chat_ref', 'openai', 'gpt-4', messages: msgs)
    expect(task.input_parameters['messages']).to be_an(Array)
    expect(task.input_parameters['messages'].length).to eq(2)
    expect(task.input_parameters['messages'].first['role']).to eq('system')
  end

  it 'includes optional parameters when set' do
    task = described_class.new('chat_ref', 'openai', 'gpt-4',
                               temperature: 0.7, max_tokens: 1000, top_p: 0.9,
                               stop_words: ['END'], json_output: true)
    expect(task.input_parameters['temperature']).to eq(0.7)
    expect(task.input_parameters['maxTokens']).to eq(1000)
    expect(task.input_parameters['topP']).to eq(0.9)
    expect(task.input_parameters['stopWords']).to eq(['END'])
    expect(task.input_parameters['jsonOutput']).to eq(true)
  end

  it 'omits nil/false optional parameters' do
    task = described_class.new('chat_ref', 'openai', 'gpt-4')
    expect(task.input_parameters).not_to have_key('temperature')
    expect(task.input_parameters).not_to have_key('maxTokens')
    expect(task.input_parameters).not_to have_key('jsonOutput')
    expect(task.input_parameters).not_to have_key('messages')
  end

  it 'includes tools when provided' do
    tools = [Conductor::Workflow::Llm::ToolSpec.new(name: 'search', description: 'Web search')]
    task = described_class.new('chat_ref', 'openai', 'gpt-4', tools: tools)
    expect(task.input_parameters['tools']).to be_an(Array)
    expect(task.input_parameters['tools'].first['name']).to eq('search')
  end

  it 'supports prompt_variables fluent method' do
    task = described_class.new('chat_ref', 'openai', 'gpt-4')
    result = task.prompt_variables({ 'name' => 'World', 'lang' => 'en' })
    expect(result).to eq(task) # fluent
    expect(task.input_parameters['promptVariables']).to eq({ 'name' => 'World', 'lang' => 'en' })
  end

  it 'supports prompt_variable fluent method' do
    task = described_class.new('chat_ref', 'openai', 'gpt-4')
    task.prompt_variable('name', 'Alice')
    expect(task.input_parameters['promptVariables']['name']).to eq('Alice')
  end

  it 'converts to WorkflowTask' do
    task = described_class.new('chat_ref', 'openai', 'gpt-4', temperature: 0.5)
    wf_task = task.to_workflow_task
    expect(wf_task.name).to eq('llm_chat_complete')
    expect(wf_task.type).to eq('LLM_CHAT_COMPLETE')
    expect(wf_task.input_parameters['llmProvider']).to eq('openai')
  end
end

RSpec.describe Conductor::Workflow::Llm::LlmTextCompleteTask do
  it 'creates with required parameters' do
    task = described_class.new('text_ref', 'openai', 'gpt-4', 'my_prompt')
    expect(task.task_type).to eq('LLM_TEXT_COMPLETE')
    expect(task.name).to eq('llm_text_complete')
    expect(task.input_parameters['llmProvider']).to eq('openai')
    expect(task.input_parameters['promptName']).to eq('my_prompt')
  end

  it 'supports prompt_variables' do
    task = described_class.new('text_ref', 'openai', 'gpt-4', 'my_prompt')
    task.prompt_variable('topic', 'Ruby')
    expect(task.input_parameters['promptVariables']['topic']).to eq('Ruby')
  end
end

RSpec.describe Conductor::Workflow::Llm::LlmGenerateEmbeddingsTask do
  it 'creates with required parameters' do
    task = described_class.new('embed_ref', 'openai', 'text-embedding-ada-002', 'Hello world')
    expect(task.task_type).to eq('LLM_GENERATE_EMBEDDINGS')
    expect(task.input_parameters['text']).to eq('Hello world')
  end

  it 'includes dimensions when set' do
    task = described_class.new('embed_ref', 'openai', 'ada-002', 'text', dimensions: 1536)
    expect(task.input_parameters['dimensions']).to eq(1536)
  end
end

RSpec.describe Conductor::Workflow::Llm::LlmIndexTextTask do
  let(:embedding_model) { Conductor::Workflow::Llm::EmbeddingModel.new(provider: 'openai', model: 'ada-002') }

  it 'creates with required parameters' do
    task = described_class.new('idx_ref', 'pinecone', 'my_index', embedding_model, 'Hello', 'doc-1')
    expect(task.task_type).to eq('LLM_INDEX_TEXT')
    expect(task.input_parameters['vectorDB']).to eq('pinecone')
    expect(task.input_parameters['index']).to eq('my_index')
    expect(task.input_parameters['embeddingModelProvider']).to eq('openai')
    expect(task.input_parameters['embeddingModel']).to eq('ada-002')
    expect(task.input_parameters['text']).to eq('Hello')
    expect(task.input_parameters['docId']).to eq('doc-1')
  end

  it 'includes optional parameters' do
    task = described_class.new('idx_ref', 'pinecone', 'my_index', embedding_model, 'text', 'doc-1',
                               namespace: 'ns1', chunk_size: 500, chunk_overlap: 50)
    expect(task.input_parameters['namespace']).to eq('ns1')
    expect(task.input_parameters['chunkSize']).to eq(500)
    expect(task.input_parameters['chunkOverlap']).to eq(50)
  end
end

RSpec.describe Conductor::Workflow::Llm::LlmIndexDocumentTask do
  let(:embedding_model) { Conductor::Workflow::Llm::EmbeddingModel.new(provider: 'openai', model: 'ada-002') }

  it 'creates with required parameters and uses LLM_INDEX_TEXT task type' do
    task = described_class.new('idx_doc_ref', 'pinecone', 'ns1', embedding_model,
                               'my_index', 'https://example.com/doc.pdf', 'application/pdf')
    expect(task.task_type).to eq('LLM_INDEX_TEXT')
    expect(task.input_parameters['url']).to eq('https://example.com/doc.pdf')
    expect(task.input_parameters['mediaType']).to eq('application/pdf')
    expect(task.input_parameters['namespace']).to eq('ns1')
  end
end

RSpec.describe Conductor::Workflow::Llm::LlmSearchIndexTask do
  it 'creates with required parameters' do
    task = described_class.new('search_ref', 'pinecone', 'ns1', 'my_index',
                               'openai', 'ada-002', 'What is Ruby?')
    expect(task.task_type).to eq('LLM_SEARCH_INDEX')
    expect(task.input_parameters['query']).to eq('What is Ruby?')
    expect(task.input_parameters['maxResults']).to eq(1) # default
  end

  it 'accepts custom max_results' do
    task = described_class.new('search_ref', 'pinecone', 'ns1', 'my_index',
                               'openai', 'ada-002', 'query', max_results: 10)
    expect(task.input_parameters['maxResults']).to eq(10)
  end
end

RSpec.describe Conductor::Workflow::Llm::LlmQueryEmbeddingsTask do
  it 'creates with required parameters' do
    embeddings = [0.1, 0.2, 0.3]
    task = described_class.new('query_ref', 'pinecone', 'my_index', embeddings)
    expect(task.task_type).to eq('LLM_GET_EMBEDDINGS')
    expect(task.input_parameters['embeddings']).to eq(embeddings)
  end
end

RSpec.describe Conductor::Workflow::Llm::LlmStoreEmbeddingsTask do
  it 'creates with required parameters' do
    embeddings = [0.1, 0.2, 0.3]
    task = described_class.new('store_ref', 'pinecone', 'my_index', embeddings)
    expect(task.task_type).to eq('LLM_STORE_EMBEDDINGS')
    expect(task.input_parameters['embeddings']).to eq(embeddings)
  end

  it 'includes optional parameters' do
    task = described_class.new('store_ref', 'pinecone', 'idx', [0.1],
                               id: 'doc-1', metadata: { 'source' => 'web' },
                               embedding_model: 'ada-002', embedding_model_provider: 'openai')
    expect(task.input_parameters['id']).to eq('doc-1')
    expect(task.input_parameters['metadata']).to eq({ 'source' => 'web' })
    expect(task.input_parameters['embeddingModel']).to eq('ada-002')
    expect(task.input_parameters['embeddingModelProvider']).to eq('openai')
  end
end

RSpec.describe Conductor::Workflow::Llm::LlmSearchEmbeddingsTask do
  it 'creates with required parameters and defaults' do
    task = described_class.new('search_emb_ref', 'pinecone', 'my_index', [0.1, 0.2])
    expect(task.task_type).to eq('LLM_SEARCH_EMBEDDINGS')
    expect(task.input_parameters['maxResults']).to eq(1) # default
  end
end

RSpec.describe Conductor::Workflow::Llm::GenerateImageTask do
  it 'creates with required parameters and defaults' do
    task = described_class.new('img_ref', 'openai', 'dall-e-3', 'A cat in space')
    expect(task.task_type).to eq('GENERATE_IMAGE')
    expect(task.name).to eq('generate_image')
    expect(task.input_parameters['prompt']).to eq('A cat in space')
    expect(task.input_parameters['width']).to eq(1024)
    expect(task.input_parameters['height']).to eq(1024)
    expect(task.input_parameters['n']).to eq(1)
    expect(task.input_parameters['outputFormat']).to eq('png')
  end

  it 'accepts custom dimensions and style' do
    task = described_class.new('img_ref', 'openai', 'dall-e-3', 'prompt',
                               width: 512, height: 512, style: 'natural', n: 2)
    expect(task.input_parameters['width']).to eq(512)
    expect(task.input_parameters['style']).to eq('natural')
    expect(task.input_parameters['n']).to eq(2)
  end
end

RSpec.describe Conductor::Workflow::Llm::GenerateAudioTask do
  it 'creates with required parameters' do
    task = described_class.new('audio_ref', 'openai', 'tts-1', text: 'Hello world', voice: 'alloy')
    expect(task.task_type).to eq('GENERATE_AUDIO')
    expect(task.input_parameters['text']).to eq('Hello world')
    expect(task.input_parameters['voice']).to eq('alloy')
    expect(task.input_parameters['n']).to eq(1)
  end
end

RSpec.describe Conductor::Workflow::Llm::GetDocumentTask do
  it 'creates with all required parameters' do
    task = described_class.new('get_doc', 'get_doc_ref', 'https://example.com/doc.pdf', 'application/pdf')
    expect(task.task_type).to eq('GET_DOCUMENT')
    expect(task.name).to eq('get_doc')
    expect(task.input_parameters['url']).to eq('https://example.com/doc.pdf')
    expect(task.input_parameters['mediaType']).to eq('application/pdf')
  end
end

RSpec.describe Conductor::Workflow::Llm::ListMcpToolsTask do
  it 'creates with required parameters' do
    task = described_class.new('list_tools_ref', 'my_mcp_server')
    expect(task.task_type).to eq('LIST_MCP_TOOLS')
    expect(task.input_parameters['mcpServer']).to eq('my_mcp_server')
  end

  it 'includes headers when provided' do
    task = described_class.new('list_tools_ref', 'server', headers: { 'Authorization' => 'Bearer token' })
    expect(task.input_parameters['headers']).to eq({ 'Authorization' => 'Bearer token' })
  end
end

RSpec.describe Conductor::Workflow::Llm::CallMcpToolTask do
  it 'creates with required parameters' do
    task = described_class.new('call_ref', 'my_mcp_server', 'get_weather')
    expect(task.task_type).to eq('CALL_MCP_TOOL')
    expect(task.input_parameters['mcpServer']).to eq('my_mcp_server')
    expect(task.input_parameters['method']).to eq('get_weather')
    expect(task.input_parameters['arguments']).to eq({}) # default
  end

  it 'passes arguments and headers' do
    task = described_class.new('call_ref', 'server', 'search',
                               arguments: { 'query' => 'hello' },
                               headers: { 'X-Key' => 'abc' })
    expect(task.input_parameters['arguments']).to eq({ 'query' => 'hello' })
    expect(task.input_parameters['headers']).to eq({ 'X-Key' => 'abc' })
  end
end
