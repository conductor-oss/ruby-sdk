#!/usr/bin/env ruby
# frozen_string_literal: true

# LLM Chat Workflow Example
#
# Demonstrates building a conversational AI workflow using Conductor's
# LLM Chat Complete task with message history.
#
# Usage:
#   bundle exec ruby examples/agentic_workflows/llm_chat.rb

require_relative '../../lib/conductor'

include Conductor::Workflow

LLM_PROVIDER = ENV.fetch('LLM_PROVIDER', 'openai')
LLM_MODEL = ENV.fetch('LLM_MODEL', 'gpt-4o-mini')

def create_chat_workflow(workflow_client, workflow_executor)
  workflow = ConductorWorkflow.new(
    workflow_client,
    'llm_chat_ruby',
    version: 1,
    executor: workflow_executor
  )
  workflow.description('Simple LLM chat workflow')

  # System message sets the AI's behavior
  system_message = ChatMessage.new(
    role: 'system',
    message: <<~MSG
      You are a helpful assistant specializing in software development.
      You provide clear, concise answers with code examples when appropriate.
      Keep responses focused and practical.
    MSG
  )

  # User message comes from workflow input
  user_message = ChatMessage.new(
    role: 'user',
    message: '${workflow.input.user_message}'
  )

  # Chat completion task
  chat_task = LlmChatCompleteTask.new(
    'chat_ref',
    LLM_PROVIDER,
    LLM_MODEL,
    messages: [system_message, user_message],
    temperature: 0.7,
    max_tokens: 1024
  )

  workflow >> chat_task
  workflow.output_parameter('response', chat_task.output('result'))

  workflow
end

def main
  config = Conductor::Configuration.new

  puts '=' * 70
  puts 'LLM Chat Workflow Example'
  puts '=' * 70
  puts "Server: #{config.server_url}"
  puts "LLM: #{LLM_PROVIDER}/#{LLM_MODEL}"
  puts

  clients = Conductor::Orkes::OrkesClients.new(config)
  workflow_executor = clients.get_workflow_executor
  workflow_client = clients.get_workflow_client

  # Create and register workflow
  workflow = create_chat_workflow(workflow_client, workflow_executor)
  workflow_executor.register_workflow(workflow, overwrite: true)
  puts "Registered workflow: #{workflow.name}"

  # Test questions
  questions = [
    'What is the difference between a Hash and an Array in Ruby?',
    'How do I handle exceptions in Ruby?',
    'Explain Ruby blocks in one sentence.'
  ]

  questions.each_with_index do |question, i|
    puts "\n--- Question #{i + 1} ---"
    puts "Q: #{question}"

    result = workflow_executor.execute(
      workflow.name,
      input: { 'user_message' => question },
      wait_for_seconds: 30
    )

    puts "A: #{result.output['response']}"
  end

  puts "\n" + '=' * 70
  puts 'Chat workflow demo complete!'
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
