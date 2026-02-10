#!/usr/bin/env ruby
# frozen_string_literal: true

# Wait for Webhook Example
#
# Demonstrates using the WAIT_FOR_WEBHOOK task to pause workflow
# execution until an external webhook is received.
#
# Usage:
#   bundle exec ruby examples/orkes/wait_for_webhook.rb

require_relative '../../lib/conductor'

include Conductor::Workflow

def create_webhook_workflow(workflow_client, workflow_executor)
  workflow = ConductorWorkflow.new(
    workflow_client,
    'webhook_workflow_ruby',
    version: 1,
    executor: workflow_executor
  )
  workflow.description('Workflow that waits for external webhook')

  # Initial task
  init = SimpleTask.new('init_process', 'init_ref')
                   .input('order_id', workflow.input('order_id'))

  # Wait for webhook - pauses until external signal received
  wait_webhook = WaitForWebhookTask.new('wait_for_payment')
                                   .input('matches', {
                                            '$.[?(@.order_id == "${workflow.input.order_id}")]' => true
                                          })

  # Process after webhook received
  process = SimpleTask.new('process_payment', 'process_ref')
                      .input('payment_data', '${wait_for_payment.output}')

  workflow >> init >> wait_webhook >> process

  workflow.output_parameter('result', '${process_ref.output}')
  workflow
end

def main
  config = Conductor::Configuration.new

  puts '=' * 70
  puts 'Wait for Webhook Example'
  puts '=' * 70
  puts "Server: #{config.server_url}"
  puts

  clients = Conductor::Orkes::OrkesClients.new(config)
  workflow_executor = clients.get_workflow_executor
  workflow_client = clients.get_workflow_client

  workflow = create_webhook_workflow(workflow_client, workflow_executor)
  workflow_executor.register_workflow(workflow, overwrite: true)
  puts "Registered workflow: #{workflow.name}"

  # Start workflow
  workflow_id = workflow_executor.start_workflow(
    Conductor::Http::Models::StartWorkflowRequest.new(
      name: workflow.name,
      version: 1,
      input: { 'order_id' => 'ORD-12345' }
    )
  )

  puts "Started workflow: #{workflow_id}"
  puts
  puts 'Workflow is now waiting for webhook...'
  puts
  puts 'To complete the workflow, send a webhook:'
  puts "  POST #{config.server_url}/webhook/#{workflow.name}"
  puts '  Body: {"order_id": "ORD-12345", "payment_status": "completed"}'
  puts
  puts "Monitor at: #{config.ui_host}/execution/#{workflow_id}"
end

if __FILE__ == $PROGRAM_NAME
  begin
    main
  rescue Conductor::ApiError => e
    puts "API Error: #{e.message}"
  rescue StandardError => e
    puts "Error: #{e.message}"
  end
end
