# frozen_string_literal: true

#
# Worker Configuration Example
#
# Demonstrates hierarchical worker configuration using environment variables.
#
# This example shows how to override worker settings at deployment time without
# changing code, using a three-tier configuration hierarchy:
#
# 1. Code-level defaults (lowest priority)
# 2. Global worker config: CONDUCTOR_WORKER_ALL_<PROPERTY>
# 3. Worker-specific config: CONDUCTOR_WORKER_<WORKER_NAME>_<PROPERTY>
#
# Usage:
#   # Run with code defaults
#   ruby worker_configuration_example.rb
#
#   # Run with global overrides
#   export CONDUCTOR_WORKER_ALL_DOMAIN=production
#   export CONDUCTOR_WORKER_ALL_POLL_INTERVAL=250
#   ruby worker_configuration_example.rb
#
#   # Run with worker-specific overrides
#   export CONDUCTOR_WORKER_ALL_DOMAIN=production
#   export CONDUCTOR_WORKER_CRITICAL_TASK_THREAD_COUNT=20
#   export CONDUCTOR_WORKER_CRITICAL_TASK_POLL_INTERVAL=100
#   ruby worker_configuration_example.rb
#

require 'bundler/setup'
require 'conductor'

#
# Example 1: Standard worker with default configuration
#
Conductor::Worker.define(
  'process_order',
  poll_interval: 1000,
  domain: 'dev',
  thread_count: 5,
  poll_timeout: 100
) do |task|
  order_id = task.input_data['order_id'] || 'unknown'
  {
    status: 'processed',
    order_id: order_id,
    worker_type: 'standard'
  }
end

#
# Example 2: High-priority worker that might need more resources in production
#
Conductor::Worker.define(
  'critical_task',
  poll_interval: 1000,
  domain: 'dev',
  thread_count: 5,
  poll_timeout: 100
) do |task|
  task_id = task.input_data['task_id'] || 'unknown'
  {
    status: 'completed',
    task_id: task_id,
    priority: 'critical'
  }
end

#
# Example 3: Background worker that can run with fewer resources
#
Conductor::Worker.define(
  'background_task',
  poll_interval: 2000,
  domain: 'dev',
  thread_count: 2,
  poll_timeout: 200
) do |task|
  job_id = task.input_data['job_id'] || 'unknown'
  {
    status: 'completed',
    job_id: job_id,
    priority: 'low'
  }
end

def print_configuration_examples
  puts
  puts '=' * 80
  puts 'Worker Configuration Hierarchy Examples'
  puts '=' * 80

  # Show current environment variables
  puts
  puts 'Current Environment Variables:'
  env_vars = ENV.select { |k, _| k.start_with?('CONDUCTOR_WORKER') }
  if env_vars.any?
    env_vars.sort.each { |key, value| puts "  #{key} = #{value}" }
  else
    puts '  (No CONDUCTOR_WORKER_* environment variables set)'
  end

  puts
  puts '-' * 80

  # Example 1: process_order configuration
  puts
  puts '1. Standard Worker (process_order):'
  puts "   Code defaults: poll_interval=1000, domain='dev', thread_count=5"

  config1 = Conductor::Worker::WorkerConfig.resolve(
    'process_order',
    poll_interval: 1000,
    domain: 'dev',
    thread_count: 5,
    poll_timeout: 100
  )
  puts
  puts '   Resolved configuration:'
  puts "     poll_interval: #{config1[:poll_interval]}"
  puts "     domain: #{config1[:domain]}"
  puts "     thread_count: #{config1[:thread_count]}"
  puts "     poll_timeout: #{config1[:poll_timeout]}"

  # Example 2: critical_task configuration
  puts
  puts '2. Critical Worker (critical_task):'
  puts "   Code defaults: poll_interval=1000, domain='dev', thread_count=5"

  config2 = Conductor::Worker::WorkerConfig.resolve(
    'critical_task',
    poll_interval: 1000,
    domain: 'dev',
    thread_count: 5,
    poll_timeout: 100
  )
  puts
  puts '   Resolved configuration:'
  puts "     poll_interval: #{config2[:poll_interval]}"
  puts "     domain: #{config2[:domain]}"
  puts "     thread_count: #{config2[:thread_count]}"
  puts "     poll_timeout: #{config2[:poll_timeout]}"

  # Example 3: background_task configuration
  puts
  puts '3. Background Worker (background_task):'
  puts "   Code defaults: poll_interval=2000, domain='dev', thread_count=2"

  config3 = Conductor::Worker::WorkerConfig.resolve(
    'background_task',
    poll_interval: 2000,
    domain: 'dev',
    thread_count: 2,
    poll_timeout: 200
  )
  puts
  puts '   Resolved configuration:'
  puts "     poll_interval: #{config3[:poll_interval]}"
  puts "     domain: #{config3[:domain]}"
  puts "     thread_count: #{config3[:thread_count]}"
  puts "     poll_timeout: #{config3[:poll_timeout]}"

  puts
  puts '-' * 80
  puts
  puts 'Configuration Priority: Worker-specific > Global > Code defaults'
  puts
  puts 'Example Environment Variables:'
  puts '  # Global override (all workers)'
  puts '  export CONDUCTOR_WORKER_ALL_DOMAIN=production'
  puts '  export CONDUCTOR_WORKER_ALL_POLL_INTERVAL=250'
  puts
  puts '  # Worker-specific override (only critical_task)'
  puts '  export CONDUCTOR_WORKER_CRITICAL_TASK_THREAD_COUNT=20'
  puts '  export CONDUCTOR_WORKER_CRITICAL_TASK_POLL_INTERVAL=100'
  puts
  puts '=' * 80
  puts
end

def print_configuration_properties
  puts
  puts '=' * 80
  puts 'Available Configuration Properties'
  puts '=' * 80
  puts
  puts 'Property             Type      Default    Description'
  puts '-' * 80
  puts 'poll_interval        Integer   100        Polling interval in milliseconds'
  puts 'thread_count         Integer   1          Max concurrent tasks per worker'
  puts 'domain               String    nil        Task domain for isolation'
  puts 'worker_id            String    auto       Unique worker identifier'
  puts 'poll_timeout         Integer   100        Server-side long poll timeout (ms)'
  puts 'register_task_def    Boolean   false      Auto-register task definition'
  puts 'paused               Boolean   false      Pause worker (stop polling)'
  puts
  puts '=' * 80
  puts
end

def main
  print_configuration_examples
  print_configuration_properties

  puts 'Configuration resolution complete!'
  puts
  puts 'To see different configurations, try setting environment variables:'
  puts
  puts '  # Test global override:'
  puts '  export CONDUCTOR_WORKER_ALL_POLL_INTERVAL=500'
  puts '  ruby worker_configuration_example.rb'
  puts
  puts '  # Test worker-specific override:'
  puts '  export CONDUCTOR_WORKER_CRITICAL_TASK_THREAD_COUNT=20'
  puts '  ruby worker_configuration_example.rb'
  puts
  puts '  # Test production-like scenario:'
  puts '  export CONDUCTOR_WORKER_ALL_DOMAIN=production'
  puts '  export CONDUCTOR_WORKER_ALL_POLL_INTERVAL=250'
  puts '  export CONDUCTOR_WORKER_CRITICAL_TASK_THREAD_COUNT=50'
  puts '  export CONDUCTOR_WORKER_CRITICAL_TASK_POLL_INTERVAL=50'
  puts '  ruby worker_configuration_example.rb'
  puts
  puts '-' * 80
  puts
  puts 'To actually run workers with the resolved configuration:'
  puts
  puts '  # Set configuration and run workers'
  puts '  export CONDUCTOR_SERVER_URL=http://localhost:8080/api'
  puts '  export CONDUCTOR_WORKER_ALL_DOMAIN=production'
  puts '  ruby worker_configuration_example.rb --run'
  puts

  # Check if --run flag is passed
  return unless ARGV.include?('--run')

  puts
  puts '=' * 80
  puts 'Running Workers with Resolved Configuration'
  puts '=' * 80
  puts

  config = Conductor::Configuration.new(
    server_api_url: ENV.fetch('CONDUCTOR_SERVER_URL', 'http://localhost:8080/api'),
    auth_key: ENV.fetch('CONDUCTOR_AUTH_KEY', nil),
    auth_secret: ENV.fetch('CONDUCTOR_AUTH_SECRET', nil)
  )

  begin
    handler = Conductor::Worker::TaskHandler.new(
      configuration: config,
      scan_for_annotated_workers: true
    )

    shutdown = false
    Signal.trap('INT') do
      puts "\nShutting down..."
      shutdown = true
      handler.stop
    end

    puts 'Workers:'
    handler.worker_names.each do |name|
      puts "  - #{name}"
    end
    puts
    puts 'Press Ctrl+C to stop...'
    puts

    handler.start
    handler.join unless shutdown
  rescue Interrupt
    puts 'Interrupted!'
  rescue StandardError => e
    puts "Error: #{e.message}"
  end

  puts 'Workers stopped.'
end

main if __FILE__ == $PROGRAM_NAME
