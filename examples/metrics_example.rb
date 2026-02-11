# frozen_string_literal: true

#
# Example demonstrating Prometheus metrics collection and HTTP endpoint exposure.
#
# This example shows how to:
# - Enable Prometheus metrics collection for task execution
# - Expose metrics via HTTP endpoint for scraping
# - Track task poll times, execution times, errors, and more
# - Integrate with Prometheus monitoring
#
# Metrics collected:
# - task_poll_total: Total number of task polls
# - task_poll_time_seconds: Task poll duration
# - task_poll_error_total: Poll errors by error type
# - task_execute_time_seconds: Task execution duration
# - task_execute_error_total: Execution errors by exception and retryability
# - task_result_size_bytes: Task result payload size
# - task_update_failed_total: Failed task updates (CRITICAL)
#
# Requirements:
#   gem 'prometheus-client'
#
# Usage:
#   1. Run this example: ruby metrics_example.rb
#   2. View metrics: curl http://localhost:9090/metrics
#   3. Configure Prometheus to scrape: http://localhost:9090/metrics
#
# Environment variables:
#   CONDUCTOR_SERVER_URL  - Conductor server URL (default: http://localhost:8080/api)
#   CONDUCTOR_AUTH_KEY    - Authentication key (optional)
#   CONDUCTOR_AUTH_SECRET - Authentication secret (optional)
#   METRICS_PORT          - Port for metrics HTTP server (default: 9090)
#

require 'bundler/setup'
require 'conductor'

# Check if prometheus-client is available
begin
  require 'prometheus/client'
  PROMETHEUS_AVAILABLE = true
rescue LoadError
  PROMETHEUS_AVAILABLE = false
  puts 'WARNING: prometheus-client gem not installed.'
  puts 'Install with: gem install prometheus-client'
  puts "Or add to Gemfile: gem 'prometheus-client'"
  puts
end

#
# Example worker tasks
#

# Async HTTP simulation worker
Conductor::Worker.define('async_http_task', poll_interval: 100, thread_count: 10) do |task|
  url = task.input_data['url'] || 'https://api.example.com/data'
  delay = task.input_data['delay'] || 0.1

  # Simulate async HTTP request
  sleep(delay)

  {
    url: url,
    status: 'success',
    timestamp: Time.now.iso8601
  }
end

# Data processor worker
Conductor::Worker.define('async_data_processor', poll_interval: 100, thread_count: 10) do |task|
  data = task.input_data['data'] || 'sample data'
  process_time = task.input_data['process_time'] || 0.5

  # Simulate data processing
  sleep(process_time)

  # Process the data
  processed = data.upcase

  {
    original: data,
    processed: processed,
    length: processed.length,
    processed_at: Time.now.iso8601
  }
end

# Batch processor worker
Conductor::Worker.define('async_batch_processor', poll_interval: 100, thread_count: 5) do |task|
  items = task.input_data['items'] || []

  # Process all items
  results = items.map do |item|
    sleep(0.01) # Simulate I/O operation
    "processed_#{item}"
  end

  {
    input_count: items.size,
    results: results,
    completed_at: Time.now.iso8601
  }
end

# CPU-bound worker
Conductor::Worker.define('sync_cpu_task', poll_interval: 100, thread_count: 5) do |task|
  n = task.input_data['n'] || 100_000

  # CPU-bound calculation
  result = (0...n).sum { |i| i * i }

  { result: result }
end

def main
  metrics_port = (ENV['METRICS_PORT'] || 9090).to_i

  # Configure Conductor connection
  config = Conductor::Configuration.new(
    server_api_url: ENV['CONDUCTOR_SERVER_URL'] || 'http://localhost:8080/api',
    auth_key: ENV.fetch('CONDUCTOR_AUTH_KEY', nil),
    auth_secret: ENV.fetch('CONDUCTOR_AUTH_SECRET', nil)
  )

  puts '=' * 80
  puts 'Metrics Collection Example'
  puts '=' * 80
  puts

  if PROMETHEUS_AVAILABLE
    # Create metrics collector with Prometheus backend
    metrics = Conductor::Worker::Telemetry::MetricsCollector.new(backend: :prometheus)

    # Start metrics HTTP server
    metrics_server = Conductor::Worker::Telemetry::MetricsServer.new(port: metrics_port)
    metrics_server.start

    puts 'Metrics mode: Prometheus HTTP'
    puts "Metrics HTTP endpoint: http://localhost:#{metrics_port}/metrics"
    puts "Health check: http://localhost:#{metrics_port}/health"
  else
    # Fall back to null metrics (logging only)
    metrics = Conductor::Worker::Telemetry::MetricsCollector.new(backend: :null)
    metrics_server = nil

    puts 'Metrics mode: Null (prometheus-client gem not installed)'
    puts 'To enable Prometheus metrics, install: gem install prometheus-client'
  end

  puts
  puts 'Workers available:'
  puts '  - async_http_task: Simulated HTTP requests (I/O-bound)'
  puts '  - async_data_processor: Data processing'
  puts '  - async_batch_processor: Batch processing'
  puts '  - sync_cpu_task: CPU-bound calculations'
  puts
  puts 'Try these commands:'
  puts "  curl http://localhost:#{metrics_port}/metrics"
  puts "  watch -n 1 'curl -s http://localhost:#{metrics_port}/metrics | grep task_poll_total'"
  puts
  puts 'Press Ctrl+C to stop...'
  puts '=' * 80
  puts

  begin
    # Create task handler with metrics enabled
    handler = Conductor::Worker::TaskHandler.new(
      configuration: config,
      scan_for_annotated_workers: true,
      event_listeners: [metrics]
    )

    # Handle graceful shutdown
    shutdown = false
    Signal.trap('INT') do
      puts "\nShutting down gracefully..."
      shutdown = true
      handler.stop
    end

    handler.start
    handler.join unless shutdown
  rescue Interrupt
    puts 'Interrupted!'
  rescue StandardError => e
    puts "Error: #{e.message}"
    puts e.backtrace.first(5).join("\n")
  ensure
    metrics_server&.stop
  end

  puts "\nWorkers stopped. Goodbye!"
end

# Alternative: Custom metrics backend example
class CustomMetricsBackend
  def initialize
    @counters = Hash.new(0)
    @histograms = Hash.new { |h, k| h[k] = [] }
    @mutex = Mutex.new
  end

  def increment(name, labels: {})
    key = "#{name}:#{labels.sort.to_h}"
    @mutex.synchronize { @counters[key] += 1 }
  end

  def observe(name, value, labels: {})
    key = "#{name}:#{labels.sort.to_h}"
    @mutex.synchronize { @histograms[key] << value }
  end

  def set(name, value, labels: {})
    key = "#{name}:#{labels.sort.to_h}"
    @mutex.synchronize { @counters[key] = value }
  end

  def report
    @mutex.synchronize do
      puts "\n--- Custom Metrics Report ---"
      puts 'Counters:'
      @counters.each { |k, v| puts "  #{k}: #{v}" }
      puts 'Histograms:'
      @histograms.each do |k, values|
        next if values.empty?

        avg = values.sum / values.size
        puts "  #{k}: count=#{values.size}, avg=#{avg.round(2)}, min=#{values.min.round(2)}, max=#{values.max.round(2)}"
      end
      puts '-----------------------------'
    end
  end
end

def main_with_custom_backend
  # Example using a custom metrics backend
  config = Conductor::Configuration.new(
    server_api_url: ENV['CONDUCTOR_SERVER_URL'] || 'http://localhost:8080/api'
  )

  custom_backend = CustomMetricsBackend.new
  metrics = Conductor::Worker::Telemetry::MetricsCollector.new(backend: custom_backend)

  puts 'Using custom metrics backend...'

  handler = Conductor::Worker::TaskHandler.new(
    configuration: config,
    scan_for_annotated_workers: true,
    event_listeners: [metrics]
  )

  # Report metrics periodically
  reporter = Thread.new do
    loop do
      sleep 30
      custom_backend.report
    end
  end

  Signal.trap('INT') do
    reporter.kill
    handler.stop
  end

  handler.start
  handler.join

  custom_backend.report
end

if __FILE__ == $PROGRAM_NAME
  # Run with Prometheus by default
  # Use main_with_custom_backend for custom backend example
  main
end
