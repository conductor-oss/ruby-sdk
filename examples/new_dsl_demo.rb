# frozen_string_literal: true

# Example demonstrating the new Ruby-idiomatic DSL for Conductor workflows
#
# This example shows how to use the new DSL which provides:
# - Method-per-type approach: simple(), http(), parallel(), etc.
# - Auto-generated reference names
# - Hash-style [] for output references
# - wf[:param] for workflow inputs
# - Block-based control flow

require 'bundler/setup'
require 'conductor'

# Define a workflow using the new DSL
# Note: executor is optional - only needed for .register() and .execute()
workflow = Conductor.workflow :order_processing_demo, version: 1 do
  # Access workflow inputs with wf[:param_name]
  # Returns: "${workflow.input.param_name}"
  order_id_input = wf[:order_id]
  user_email_input = wf[:user_email]

  # Simple tasks return TaskRef objects
  # Access task outputs with task[:field_name]
  user = simple :get_user, user_id: order_id_input
  order = simple :validate_order,
                 order_id: order_id_input,
                 user_email: user[:email]

  # HTTP tasks with fluent syntax
  api_response = http :call_payment_api,
                      url: 'https://api.payment.example.com/charge',
                      method: :post,
                      body: {
                        amount: order[:total],
                        currency: 'USD',
                        customer: user[:id]
                      },
                      headers: {
                        'Authorization' => 'Bearer ${workflow.input.api_key}',
                        'Content-Type' => 'application/json'
                      }

  # Parallel execution - tasks run concurrently
  parallel do
    simple :ship_order,
           order_id: order[:id],
           address: order[:shipping_address]

    simple :send_confirmation_email,
           to: user_email_input,
           order_id: order[:id]

    simple :update_inventory,
           product_id: order[:product_id],
           quantity: order[:quantity]
  end

  # Switch/decision based on output value
  decide order[:region] do
    on 'US' do
      simple :calculate_us_tax, amount: order[:total]
      simple :apply_us_shipping
    end

    on 'EU' do
      simple :calculate_vat, amount: order[:total]
      simple :apply_eu_shipping
    end

    on 'UK' do
      simple :calculate_uk_tax, amount: order[:total]
      simple :apply_uk_shipping
    end

    otherwise do
      simple :apply_international_shipping
      terminate :completed, 'International order processed with standard shipping'
    end
  end

  # Set workflow variables
  set(
    order_status: 'completed',
    processed_at: '${CPEWF_EPOCH}',
    processor_id: wf[:worker_id]
  )

  # Define workflow outputs
  output(
    order_id: order[:id],
    status: 'processed',
    total: order[:total],
    payment_result: api_response[:transaction_id]
  )
end

# Display workflow information
puts "Workflow created: #{workflow.name} (version #{workflow.version})"
puts "Task count: #{workflow.builder.tasks.size}"

# Convert to WorkflowDef to see the generated structure
workflow_def = workflow.to_workflow_def
puts "\nGenerated WorkflowDef:"
puts "  Name: #{workflow_def.name}"
puts "  Version: #{workflow_def.version}"
puts "  Tasks: #{workflow_def.tasks.size}"
puts "\nFirst 3 tasks:"
workflow_def.tasks.take(3).each_with_index do |task, idx|
  puts "  #{idx + 1}. #{task.type}: #{task.task_reference_name}"
end

puts "\nOutput parameters: #{workflow_def.output_parameters.keys.join(', ')}"

puts "\n✓ DSL example completed successfully!"
puts "\nTo register and execute this workflow, provide an executor:"
puts <<~EXAMPLE
  
  # Create executor with configuration
  config = Conductor::Configuration.new
  config.server_url = 'http://localhost:8080/api'
  executor = Conductor::Workflow::WorkflowExecutor.new(config)
  
  # Define workflow with executor
  workflow = Conductor.workflow :order_processing_demo, version: 1, executor: executor do
    # ... workflow definition ...
  end
  
  # Register the workflow
  workflow.register(overwrite: true)
  
  # Execute the workflow
  result = workflow.execute(input: {
    order_id: '12345',
    user_email: 'customer@example.com',
    api_key: 'secret_key',
    worker_id: 'worker-001'
  })
  
  puts "Workflow status: \#{result.status}"
EXAMPLE
