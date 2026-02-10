#!/usr/bin/env ruby
# frozen_string_literal: true

# Metadata Management Journey
#
# Demonstrates all metadata operations: workflow definitions,
# task definitions, and tagging.
#
# Usage:
#   bundle exec ruby examples/metadata_journey.rb

require_relative '../lib/conductor'

class MetadataJourney
  def initialize
    @config = Conductor::Configuration.new
    @clients = Conductor::Orkes::OrkesClients.new(@config)
    @metadata = @clients.get_metadata_client

    puts '=' * 70
    puts 'Metadata Management Journey'
    puts '=' * 70
    puts "Server: #{@config.server_url}"
    puts
  end

  def run
    manage_task_definitions
    manage_workflow_definitions
    work_with_tags
    cleanup
  end

  private

  def manage_task_definitions
    puts "\n--- Task Definitions ---"

    # Create task definitions
    tasks = [
      {
        'name' => 'ruby_process_order',
        'description' => 'Process incoming orders',
        'retryCount' => 3,
        'retryLogic' => 'FIXED',
        'retryDelaySeconds' => 10,
        'timeoutSeconds' => 300,
        'responseTimeoutSeconds' => 60
      },
      {
        'name' => 'ruby_send_notification',
        'description' => 'Send customer notifications',
        'retryCount' => 2,
        'timeoutSeconds' => 60
      },
      {
        'name' => 'ruby_update_inventory',
        'description' => 'Update inventory counts',
        'retryCount' => 5,
        'timeoutSeconds' => 120
      }
    ]

    tasks.each do |task|
      @metadata.register_task_def(task)
      puts "Created task: #{task['name']}"
    end

    # Get a specific task
    task = @metadata.get_task_def('ruby_process_order')
    puts "\nRetrieved task: #{task['name'] || task.name}"

    # Get all tasks
    all_tasks = @metadata.get_all_task_defs
    puts "Total tasks in system: #{all_tasks.length}"

    @created_tasks = tasks.map { |t| t['name'] }
  end

  def manage_workflow_definitions
    puts "\n--- Workflow Definitions ---"

    # Create workflow definition
    workflow_def = {
      'name' => 'ruby_order_pipeline',
      'description' => 'Complete order processing pipeline',
      'version' => 1,
      'schemaVersion' => 2,
      'tasks' => [
        {
          'name' => 'ruby_process_order',
          'taskReferenceName' => 'process_ref',
          'type' => 'SIMPLE',
          'inputParameters' => {
            'orderId' => '${workflow.input.orderId}'
          }
        },
        {
          'name' => 'ruby_update_inventory',
          'taskReferenceName' => 'inventory_ref',
          'type' => 'SIMPLE',
          'inputParameters' => {
            'items' => '${process_ref.output.items}'
          }
        },
        {
          'name' => 'ruby_send_notification',
          'taskReferenceName' => 'notify_ref',
          'type' => 'SIMPLE',
          'inputParameters' => {
            'customerId' => '${workflow.input.customerId}',
            'status' => '${inventory_ref.output.status}'
          }
        }
      ],
      'outputParameters' => {
        'orderStatus' => '${notify_ref.output.status}'
      },
      'timeoutSeconds' => 600
    }

    @metadata.register_workflow_def(workflow_def, overwrite: true)
    puts "Created workflow: #{workflow_def['name']}"

    # Get the workflow
    wf = @metadata.get_workflow_def('ruby_order_pipeline')
    puts "Retrieved workflow: #{wf['name'] || wf.name}"

    # Get all workflows
    all_workflows = @metadata.get_all_workflow_defs
    puts "Total workflows in system: #{all_workflows.length}"

    @created_workflow = workflow_def['name']
  end

  def work_with_tags
    puts "\n--- Working with Tags ---"

    # Tag a workflow
    tags = [
      { 'key' => 'team', 'value' => 'orders' },
      { 'key' => 'environment', 'value' => 'development' }
    ]

    begin
      @metadata.add_workflow_tag('ruby_order_pipeline', tags.first)
      puts "Added tag to workflow: #{tags.first['key']}=#{tags.first['value']}"

      # Get workflow tags
      wf_tags = @metadata.get_workflow_tags('ruby_order_pipeline')
      puts "Workflow tags: #{wf_tags.length}"
    rescue StandardError => e
      puts "Tag operations: #{e.message}"
    end
  end

  def cleanup
    puts "\n--- Cleanup ---"

    # Delete workflow
    begin
      @metadata.unregister_workflow_def(@created_workflow, 1)
      puts "Deleted workflow: #{@created_workflow}"
    rescue StandardError => e
      puts "Could not delete workflow: #{e.message}"
    end

    # Delete tasks
    @created_tasks&.each do |name|
      begin
        @metadata.unregister_task_def(name)
        puts "Deleted task: #{name}"
      rescue StandardError => e
        puts "Could not delete #{name}: #{e.message}"
      end
    end

    puts "\nMetadata journey complete!"
  end
end

if __FILE__ == $PROGRAM_NAME
  begin
    MetadataJourney.new.run
  rescue Conductor::ApiError => e
    puts "API Error: #{e.message}"
  rescue StandardError => e
    puts "Error: #{e.message}"
    puts e.backtrace.first(3).join("\n")
  end
end
