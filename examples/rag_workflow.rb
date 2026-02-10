#!/usr/bin/env ruby
# frozen_string_literal: true

# RAG (Retrieval Augmented Generation) Workflow Example
#
# This example demonstrates a complete RAG pipeline using Conductor:
# 1. User provides text content as workflow input
# 2. Conductor indexes the text into a vector DB using embeddings
# 3. A search query retrieves relevant context from the vector store
# 4. An LLM generates an answer grounded in the retrieved context
#
# Prerequisites:
# 1. Orkes Conductor server with AI/LLM support
# 2. Configure integrations in Conductor:
#    - Vector DB integration (e.g., "pinecone", "weaviate", "pgvector")
#    - LLM provider (e.g., "openai", "azure_openai", "cohere")
#
# Usage:
#   bundle exec ruby examples/rag_workflow.rb

require_relative '../lib/conductor'

include Conductor::Workflow

# Configuration constants - adjust based on your integrations
VECTOR_DB = 'pinecone'
VECTOR_INDEX = 'demo_index'
NAMESPACE = 'demo_namespace'
EMBEDDING_PROVIDER = 'openai'
EMBEDDING_MODEL = 'text-embedding-3-small'
LLM_PROVIDER = 'openai'
LLM_MODEL = 'gpt-4o-mini'

def create_rag_workflow(workflow_client, workflow_executor)
  workflow = ConductorWorkflow.new(
    workflow_client,
    'rag_pipeline_ruby',
    version: 1,
    executor: workflow_executor
  )
  workflow.description('RAG pipeline: index text -> search -> generate answer')
  workflow.timeout_seconds(300)

  # Step 1: Index the input text into vector DB
  index_task = LlmIndexTextTask.new(
    'index_text_ref',
    VECTOR_DB,
    VECTOR_INDEX,
    namespace: NAMESPACE,
    embedding_model: EMBEDDING_MODEL,
    embedding_model_provider: EMBEDDING_PROVIDER
  )
  index_task.input('text', workflow.input('text'))
  index_task.input('docId', workflow.input('doc_id'))

  # Step 2: Wait for vector DB to commit (eventual consistency)
  wait_task = WaitTask.new('wait_for_index', wait_for_seconds: 3)

  # Step 3: Search the index with the user's question
  search_task = LlmSearchIndexTask.new(
    'search_index_ref',
    VECTOR_DB,
    VECTOR_INDEX,
    namespace: NAMESPACE,
    embedding_model: EMBEDDING_MODEL,
    embedding_model_provider: EMBEDDING_PROVIDER
  )
  search_task.input('query', workflow.input('question'))
  search_task.input('maxResults', 5)

  # Step 4: Generate answer using retrieved context
  system_prompt = <<~PROMPT
    You are a helpful assistant. Answer the user's question based ONLY on the#{' '}
    context provided below. If the context does not contain enough information, say so.

    Context from knowledge base:
    ${search_index_ref.output.result}
  PROMPT

  answer_task = LlmChatCompleteTask.new(
    'generate_answer_ref',
    LLM_PROVIDER,
    LLM_MODEL,
    messages: [
      ChatMessage.new(role: 'system', message: system_prompt),
      ChatMessage.new(role: 'user', message: workflow.input('question'))
    ],
    temperature: 0.2,
    max_tokens: 1024
  )

  # Chain tasks
  workflow >> index_task >> wait_task >> search_task >> answer_task

  # Define outputs
  workflow.output_parameter('retrieved_context', search_task.output('result'))
  workflow.output_parameter('answer', answer_task.output('result'))

  workflow
end

def main
  config = Conductor::Configuration.new

  puts '=' * 70
  puts 'Conductor Ruby SDK - RAG Workflow Example'
  puts '=' * 70
  puts
  puts "Server: #{config.server_url}"
  puts "Vector DB: #{VECTOR_DB}"
  puts "LLM Provider: #{LLM_PROVIDER}"
  puts

  clients = Conductor::Orkes::OrkesClients.new(config)
  workflow_executor = clients.get_workflow_executor
  workflow_client = clients.get_workflow_client

  # Create and register workflow
  workflow = create_rag_workflow(workflow_client, workflow_executor)
  workflow_executor.register_workflow(workflow, overwrite: true)
  puts "Registered workflow: #{workflow.name}"

  # Sample document and question
  sample_text = <<~TEXT
    Ruby is a dynamic, open source programming language with a focus on simplicity#{' '}
    and productivity. It has an elegant syntax that is natural to read and easy to write.
    Ruby was created by Yukihiro "Matz" Matsumoto in the mid-1990s in Japan.
    Ruby on Rails, often simply called Rails, is a web application framework written in Ruby.
    Rails was created by David Heinemeier Hansson and released in 2004.
  TEXT

  question = 'Who created Ruby and when?'

  puts
  puts 'Executing RAG workflow...'
  puts "Document: #{sample_text.length} characters"
  puts "Question: #{question}"

  result = workflow_executor.execute(
    workflow.name,
    input: {
      'text' => sample_text,
      'doc_id' => 'ruby_intro',
      'question' => question
    },
    wait_for_seconds: 60
  )

  puts
  puts '-' * 70
  puts "Status: #{result.status}"
  puts "Answer: #{result.output['answer']}"
  puts '-' * 70
  puts
  puts "View execution: #{config.ui_host}/execution/#{result.workflow_id}"
end

if __FILE__ == $PROGRAM_NAME
  begin
    main
  rescue Conductor::ApiError => e
    puts "API Error: #{e.message}"
  rescue StandardError => e
    puts "Error: #{e.message}"
    puts e.backtrace.first(3).join("\n")
  end
end
