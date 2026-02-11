#!/usr/bin/env ruby
# frozen_string_literal: true

# LLM Chat Workflow Example
#
# Demonstrates building a conversational AI workflow using the new Ruby DSL
# with LLM Chat Complete task and message history.
#
# New DSL Features Shown:
# - llm_chat() method with automatic message conversion
# - Pass messages as simple hashes instead of ChatMessage objects
#
# Usage:
#   bundle exec ruby examples/agentic_workflows/llm_chat.rb

require_relative '../../lib/conductor'

LLM_PROVIDER = ENV.fetch('LLM_PROVIDER', 'openai')
LLM_MODEL = ENV.fetch('LLM_MODEL', 'gpt-4o-mini')

def create_chat_workflow(executor)
  # Create workflow using the new Ruby-idiomatic DSL
  Conductor.workflow :llm_chat_ruby, version: 1, executor: executor do
    description 'Simple LLM chat workflow using new DSL'

    # Chat completion task with messages as hashes (auto-converted)
    # The DSL automatically converts hash messages to ChatMessage objects
    chat = llm_chat :chat,
                    provider: LLM_PROVIDER,
                    model: LLM_MODEL,
                    messages: [
                      {
                        role: :system,
                        message: <<~MSG
                          You are a helpful assistant specializing in software development.
                          You provide clear, concise answers with code examples when appropriate.
                          Keep responses focused and practical.
                        MSG
                      },
                      {
                        role: :user,
                        message: '${workflow.input.user_message}'
                      }
                    ],
                    temperature: 0.7,
                    max_tokens: 1024

    # Set workflow output to the chat response
    output response: chat[:result]
  end
end

def main
  config = Conductor::Configuration.new

  puts '=' * 70
  puts 'LLM Chat Workflow Example (New DSL)'
  puts '=' * 70
  puts "Server: #{config.server_url}"
  puts "LLM: #{LLM_PROVIDER}/#{LLM_MODEL}"
  puts

  clients = Conductor::Orkes::OrkesClients.new(config)
  workflow_executor = clients.get_workflow_executor

  # Create workflow with executor (required for register/execute)
  workflow = create_chat_workflow(workflow_executor)

  # Register workflow
  workflow.register(overwrite: true)
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

    # Execute using the workflow's execute method
    result = workflow.execute(
      input: { 'user_message' => question },
      wait_for_seconds: 30
    )

    puts "A: #{result.output['response']}"
  end

  puts "\n#{'=' * 70}"
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
