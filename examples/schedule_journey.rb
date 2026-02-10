#!/usr/bin/env ruby
# frozen_string_literal: true

# Schedule Management Journey - Comprehensive Example
#
# Demonstrates all Scheduler APIs through building an automated
# order processing system with scheduled workflows.
#
# APIs Covered:
# - save_schedule, get_schedule, get_all_schedules, delete_schedule
# - pause_schedule, resume_schedule, pause_all_schedules, resume_all_schedules
# - get_next_few_schedule_execution_times, search_schedule_executions
# - set_scheduler_tags, get_scheduler_tags, delete_scheduler_tags
#
# Usage:
#   bundle exec ruby examples/schedule_journey.rb

require_relative '../lib/conductor'

class ScheduleJourney
  def initialize
    @config = Conductor::Configuration.new
    @clients = Conductor::Orkes::OrkesClients.new(@config)
    @scheduler = @clients.get_scheduler_client
    @metadata = @clients.get_metadata_client
    @created_schedules = []

    puts '=' * 70
    puts 'Schedule Management Journey'
    puts '=' * 70
    puts "Server: #{@config.server_url}"
    puts
  end

  def run
    setup_workflow
    create_schedules
    manage_schedules
    work_with_tags
    preview_and_search
    cleanup
  end

  private

  def setup_workflow
    puts "\n--- Setting up test workflow ---"

    # Create a simple workflow for scheduling
    workflow_def = Conductor::Http::Models::WorkflowDef.new(
      name: 'scheduled_order_processor',
      version: 1,
      description: 'Process orders on schedule',
      tasks: [
        {
          'name' => 'process_orders',
          'taskReferenceName' => 'process_ref',
          'type' => 'HTTP',
          'inputParameters' => {
            'http_request' => {
              'uri' => 'https://httpbin.org/post',
              'method' => 'POST',
              'body' => { 'timestamp' => '${workflow.input.timestamp}' }
            }
          }
        }
      ]
    )

    @metadata.register_workflow_def(workflow_def, overwrite: true)
    puts "Created workflow: #{workflow_def.name}"
  end

  def create_schedules
    puts "\n--- Creating Schedules ---"

    # Schedule 1: Every minute (for demo)
    schedule1 = {
      'name' => 'order_processor_minutely',
      'cronExpression' => '0 * * * * ?',  # Every minute
      'startWorkflowRequest' => {
        'name' => 'scheduled_order_processor',
        'version' => 1,
        'input' => { 'type' => 'minutely' }
      },
      'paused' => true,  # Start paused for demo
      'scheduleStartTime' => (Time.now.to_i * 1000),
      'zoneId' => 'America/New_York'
    }

    @scheduler.save_schedule(schedule1)
    @created_schedules << schedule1['name']
    puts "Created schedule: #{schedule1['name']} (every minute)"

    # Schedule 2: Daily at midnight
    schedule2 = {
      'name' => 'order_processor_daily',
      'cronExpression' => '0 0 0 * * ?',  # Daily at midnight
      'startWorkflowRequest' => {
        'name' => 'scheduled_order_processor',
        'version' => 1,
        'input' => { 'type' => 'daily' }
      },
      'paused' => true
    }

    @scheduler.save_schedule(schedule2)
    @created_schedules << schedule2['name']
    puts "Created schedule: #{schedule2['name']} (daily at midnight)"

    # Schedule 3: Weekly on Monday
    schedule3 = {
      'name' => 'order_processor_weekly',
      'cronExpression' => '0 0 9 ? * MON',  # Monday at 9 AM
      'startWorkflowRequest' => {
        'name' => 'scheduled_order_processor',
        'version' => 1,
        'input' => { 'type' => 'weekly' }
      },
      'paused' => true
    }

    @scheduler.save_schedule(schedule3)
    @created_schedules << schedule3['name']
    puts "Created schedule: #{schedule3['name']} (weekly on Monday)"
  end

  def manage_schedules
    puts "\n--- Managing Schedules ---"

    # Get a specific schedule
    schedule = @scheduler.get_schedule('order_processor_minutely')
    puts "Retrieved schedule: #{schedule['name']}"
    puts "  Cron: #{schedule['cronExpression']}"
    puts "  Paused: #{schedule['paused']}"

    # Get all schedules
    all_schedules = @scheduler.get_all_schedules
    puts "\nAll schedules (#{all_schedules.length} total):"
    all_schedules.first(5).each do |s|
      name = s.is_a?(Hash) ? s['name'] : s.name
      puts "  - #{name}"
    end

    # Pause and resume individual schedule
    puts "\nPausing order_processor_minutely..."
    @scheduler.pause_schedule('order_processor_minutely')

    puts "Resuming order_processor_minutely..."
    begin
      @scheduler.resume_schedule('order_processor_minutely')
    rescue Conductor::ApiError => e
      puts "  Note: #{e.message}" if e.message.include?('404')
    end

    # Pause all schedules
    puts "\nPausing all schedules..."
    @scheduler.pause_all_schedules

    # Resume all schedules
    puts "Resuming all schedules..."
    @scheduler.resume_all_schedules
  end

  def work_with_tags
    puts "\n--- Working with Tags ---"

    tags = [
      { 'key' => 'environment', 'value' => 'production' },
      { 'key' => 'team', 'value' => 'orders' }
    ]

    # Set tags
    puts "Setting tags on order_processor_daily..."
    @scheduler.set_scheduler_tags(tags, 'order_processor_daily')

    # Get tags
    retrieved_tags = @scheduler.get_scheduler_tags('order_processor_daily')
    puts "Retrieved tags:"
    retrieved_tags.each do |tag|
      key = tag.is_a?(Hash) ? tag['key'] : tag.key
      value = tag.is_a?(Hash) ? tag['value'] : tag.value
      puts "  #{key}: #{value}"
    end

    # Delete tags
    puts "Deleting tags..."
    @scheduler.delete_scheduler_tags(tags, 'order_processor_daily')
  end

  def preview_and_search
    puts "\n--- Preview and Search ---"

    # Get next execution times
    puts "Next 5 execution times for order_processor_minutely:"
    begin
      times = @scheduler.get_next_few_schedule_execution_times(
        '0 * * * * ?',
        limit: 5
      )
      times.first(5).each { |t| puts "  - #{Time.at(t / 1000)}" }
    rescue StandardError => e
      puts "  Could not get execution times: #{e.message}"
    end

    # Search executions
    puts "\nSearching schedule executions..."
    begin
      results = @scheduler.search_schedule_executions(
        start: 0,
        size: 10,
        query: '*:*'
      )
      count = results.is_a?(Hash) ? results['totalHits'] : results.total_hits
      puts "Found #{count || 0} executions"
    rescue StandardError => e
      puts "  Search returned: #{e.message}"
    end
  end

  def cleanup
    puts "\n--- Cleanup ---"

    @created_schedules.each do |name|
      begin
        @scheduler.delete_schedule(name)
        puts "Deleted schedule: #{name}"
      rescue StandardError => e
        puts "Could not delete #{name}: #{e.message}"
      end
    end

    puts "\nSchedule journey complete!"
  end
end

if __FILE__ == $PROGRAM_NAME
  begin
    ScheduleJourney.new.run
  rescue Conductor::ApiError => e
    puts "API Error: #{e.message}"
  rescue StandardError => e
    puts "Error: #{e.message}"
    puts e.backtrace.first(3).join("\n")
  end
end
