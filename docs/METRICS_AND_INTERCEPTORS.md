# Metrics and Interceptors Guide

This guide explains how to use the metrics and interceptor system in the Conductor Ruby SDK to monitor worker performance, track errors, and implement custom observability.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Event Types](#event-types)
- [Creating Custom Interceptors](#creating-custom-interceptors)
- [Metrics Collection](#metrics-collection)
- [Prometheus Integration](#prometheus-integration)
- [Advanced Use Cases](#advanced-use-cases)
- [Best Practices](#best-practices)

---

## Overview

The Conductor Ruby SDK provides an event-driven interceptor system that allows you to:

- **Monitor performance** - Track polling times, execution durations, error rates
- **Implement custom logging** - Add structured logging for task execution
- **Track errors** - Send failures to error tracking services (Sentry, Bugsnag, etc.)
- **Collect metrics** - Export to Prometheus, Datadog, or custom backends
- **Build alerting** - Monitor SLAs and trigger alerts on violations

### How It Works

```
TaskRunner
    │
    │ publishes events
    ▼
SyncEventDispatcher ──────► Listener 1 (MetricsCollector)
                    ──────► Listener 2 (LoggingInterceptor)
                    ──────► Listener 3 (SentryInterceptor)
```

When a worker polls for tasks, executes them, or encounters errors, events are published to all registered listeners. Listeners can then process these events independently.

---

## Quick Start

### Basic Logging Interceptor

```ruby
require 'conductor'
require 'logger'

# Create a simple logging interceptor
class LoggingInterceptor
  def initialize
    @logger = Logger.new($stdout)
  end

  def on_task_execution_started(event)
    @logger.info("Task started: #{event.task_id} (#{event.task_type})")
  end

  def on_task_execution_completed(event)
    @logger.info("Task completed: #{event.task_id} in #{event.duration_ms.round(2)}ms")
  end

  def on_task_execution_failure(event)
    @logger.error("Task failed: #{event.task_id} - #{event.cause.message}")
  end
end

# Create configuration
config = Conductor::Configuration.new(
  server_api_url: ENV['CONDUCTOR_SERVER_URL'],
  auth_key: ENV['CONDUCTOR_AUTH_KEY'],
  auth_secret: ENV['CONDUCTOR_AUTH_SECRET']
)

# Define a worker
Conductor::Worker.define('my_task') do |task|
  # Worker logic
  { result: 'success' }
end

# Create handler with interceptor
handler = Conductor::Worker::TaskHandler.new(
  configuration: config,
  event_listeners: [LoggingInterceptor.new]
)

# Start workers
handler.start
handler.join
```

---

## Event Types

The SDK publishes the following events during worker execution:

### Poll Events

| Event | When Published | Key Attributes |
|-------|---------------|----------------|
| `PollStarted` | Before polling for tasks | `task_type`, `worker_id`, `poll_count` |
| `PollCompleted` | After successful poll | `task_type`, `duration_ms`, `tasks_received` |
| `PollFailure` | When poll fails | `task_type`, `duration_ms`, `cause` |

### Execution Events

| Event | When Published | Key Attributes |
|-------|---------------|----------------|
| `TaskExecutionStarted` | Before task execution | `task_type`, `task_id`, `worker_id`, `workflow_instance_id` |
| `TaskExecutionCompleted` | After successful execution | `task_type`, `task_id`, `duration_ms`, `output_size_bytes` |
| `TaskExecutionFailure` | When execution fails | `task_type`, `task_id`, `duration_ms`, `cause`, `is_retryable` |

### Critical Events

| Event | When Published | Key Attributes |
|-------|---------------|----------------|
| `TaskUpdateFailure` | When result update fails after all retries | `task_type`, `task_id`, `retry_count`, `task_result` |

**Important**: `TaskUpdateFailure` is a critical event indicating that a task result was lost. You should always handle this event to prevent silent data loss.

---

## Creating Custom Interceptors

### Basic Structure

An interceptor is any object that responds to one or more `on_*` methods:

```ruby
class MyInterceptor
  # Implement only the methods you need
  
  def on_poll_started(event)
    # Called before each poll
  end

  def on_poll_completed(event)
    # Called after successful poll
  end

  def on_poll_failure(event)
    # Called when poll fails
  end

  def on_task_execution_started(event)
    # Called before task execution
  end

  def on_task_execution_completed(event)
    # Called after successful execution
  end

  def on_task_execution_failure(event)
    # Called when execution fails
  end

  def on_task_update_failure(event)
    # Called when result update fails (CRITICAL)
  end
end
```

### Error Tracking Interceptor (Sentry)

```ruby
require 'sentry-ruby'

class SentryInterceptor
  def on_task_execution_failure(event)
    Sentry.capture_exception(event.cause, extra: {
      task_id: event.task_id,
      task_type: event.task_type,
      workflow_instance_id: event.workflow_instance_id,
      duration_ms: event.duration_ms,
      is_retryable: event.is_retryable
    })
  end

  def on_task_update_failure(event)
    Sentry.capture_message(
      "CRITICAL: Task result lost after #{event.retry_count} retries",
      level: :fatal,
      extra: {
        task_id: event.task_id,
        task_type: event.task_type,
        workflow_instance_id: event.workflow_instance_id
      }
    )
  end
end
```

### Structured Logging Interceptor

```ruby
require 'json'

class StructuredLoggingInterceptor
  def initialize(output: $stdout)
    @output = output
  end

  def on_task_execution_started(event)
    log('task_started', event)
  end

  def on_task_execution_completed(event)
    log('task_completed', event, duration_ms: event.duration_ms)
  end

  def on_task_execution_failure(event)
    log('task_failed', event,
        duration_ms: event.duration_ms,
        error: event.cause.class.name,
        message: event.cause.message,
        retryable: event.is_retryable)
  end

  private

  def log(action, event, extra = {})
    entry = {
      timestamp: event.timestamp.iso8601(3),
      action: action,
      task_type: event.task_type,
      task_id: event.task_id,
      worker_id: event.worker_id,
      workflow_instance_id: event.workflow_instance_id,
      **extra
    }
    @output.puts(entry.to_json)
  end
end
```

---

## Metrics Collection

### Using the Built-in MetricsCollector

The SDK includes a `MetricsCollector` that tracks key metrics:

```ruby
require 'conductor'

# Create metrics collector (uses NullBackend by default)
metrics = Conductor::Worker::Telemetry::MetricsCollector.new

# Use with TaskHandler
handler = Conductor::Worker::TaskHandler.new(
  configuration: config,
  event_listeners: [metrics]
)
```

### Tracked Metrics

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `task_poll_total` | Counter | `task_type` | Total poll operations |
| `task_poll_time_seconds` | Histogram | `task_type` | Poll latency |
| `task_poll_error_total` | Counter | `task_type`, `error` | Poll failures |
| `task_execute_time_seconds` | Histogram | `task_type` | Execution time |
| `task_execute_error_total` | Counter | `task_type`, `exception`, `retryable` | Execution failures |
| `task_result_size_bytes` | Histogram | `task_type` | Output size |
| `task_update_failed_total` | Counter | `task_type` | Failed result updates |

### Custom Metrics Backend

You can create a custom backend by implementing three methods:

```ruby
class DatadogBackend
  def initialize(statsd_client)
    @statsd = statsd_client
  end

  def increment(name, labels: {})
    tags = labels.map { |k, v| "#{k}:#{v}" }
    @statsd.increment(name, tags: tags)
  end

  def observe(name, value, labels: {})
    tags = labels.map { |k, v| "#{k}:#{v}" }
    @statsd.histogram(name, value, tags: tags)
  end

  def set(name, value, labels: {})
    tags = labels.map { |k, v| "#{k}:#{v}" }
    @statsd.gauge(name, value, tags: tags)
  end
end

# Use with MetricsCollector
require 'datadog/statsd'
statsd = Datadog::Statsd.new('localhost', 8125)
metrics = Conductor::Worker::Telemetry::MetricsCollector.new(
  backend: DatadogBackend.new(statsd)
)
```

---

## Prometheus Integration

### Setup

Add the `prometheus-client` gem to your Gemfile:

```ruby
gem 'prometheus-client', '~> 4.0'
```

### Basic Usage

```ruby
require 'conductor'

# Create metrics collector with Prometheus backend
metrics = Conductor::Worker::Telemetry::MetricsCollector.new(backend: :prometheus)

# Start metrics HTTP server
metrics_server = Conductor::Worker::Telemetry::MetricsServer.new(port: 9090)
metrics_server.start

# Create handler with metrics
handler = Conductor::Worker::TaskHandler.new(
  configuration: config,
  event_listeners: [metrics]
)

handler.start
handler.join

# Cleanup
metrics_server.stop
```

### Metrics Endpoints

The MetricsServer exposes:

- `GET /metrics` - Prometheus metrics in text format
- `GET /health` - Health check endpoint (`{"status":"healthy"}`)

### Kubernetes Integration

```yaml
# Pod annotations for Prometheus scraping
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9090"
    prometheus.io/path: "/metrics"
```

### Custom Prometheus Registry

```ruby
require 'prometheus/client'

# Use a custom registry
registry = Prometheus::Client::Registry.new
backend = Conductor::Worker::Telemetry::PrometheusBackend.new(registry: registry)
metrics = Conductor::Worker::Telemetry::MetricsCollector.new(backend: backend)
```

---

## Advanced Use Cases

### SLA Monitor

Alert when tasks exceed duration thresholds:

```ruby
class SLAMonitor
  def initialize(thresholds:, alerter:)
    @thresholds = thresholds  # { 'task_type' => max_ms }
    @alerter = alerter
  end

  def on_task_execution_completed(event)
    threshold = @thresholds[event.task_type]
    return unless threshold && event.duration_ms > threshold

    @alerter.alert(
      type: :sla_violation,
      task_type: event.task_type,
      task_id: event.task_id,
      duration_ms: event.duration_ms,
      threshold_ms: threshold
    )
  end
end

# Usage
sla_monitor = SLAMonitor.new(
  thresholds: {
    'process_order' => 5000,
    'send_email' => 2000
  },
  alerter: SlackAlerter.new(webhook_url: ENV['SLACK_WEBHOOK'])
)
```

### Cost Tracker

Track compute costs per task type:

```ruby
class CostTracker
  def initialize(cost_per_ms: {})
    @cost_per_ms = cost_per_ms  # { 'task_type' => cost_per_ms }
    @costs = Hash.new(0.0)
    @mutex = Mutex.new
  end

  def on_task_execution_completed(event)
    rate = @cost_per_ms[event.task_type] || 0.0001
    cost = rate * event.duration_ms
    @mutex.synchronize { @costs[event.task_type] += cost }
  end

  def report
    @mutex.synchronize { @costs.dup }
  end
end
```

### Retry Tracker

Monitor retry patterns:

```ruby
class RetryTracker
  def initialize
    @retries = Hash.new { |h, k| h[k] = [] }
    @mutex = Mutex.new
  end

  def on_task_execution_failure(event)
    return unless event.is_retryable

    @mutex.synchronize do
      @retries[event.task_type] << {
        task_id: event.task_id,
        error: event.cause.class.name,
        timestamp: event.timestamp
      }
    end
  end

  def retry_rate(task_type, window_seconds: 300)
    @mutex.synchronize do
      cutoff = Time.now - window_seconds
      recent = @retries[task_type].select { |r| r[:timestamp] > cutoff }
      recent.size
    end
  end
end
```

---

## Best Practices

### 1. Keep Interceptors Fast

Interceptors run synchronously in the worker thread. Keep processing fast to avoid impacting task execution:

```ruby
# BAD: Slow synchronous HTTP call
def on_task_execution_completed(event)
  HTTParty.post('https://analytics.example.com', body: event.to_h.to_json)
end

# GOOD: Queue for background processing
def on_task_execution_completed(event)
  @queue << event.to_h
end
```

### 2. Handle Errors in Interceptors

Errors in interceptors are caught and logged but don't affect other interceptors:

```ruby
def on_task_execution_completed(event)
  # Safe to raise - won't crash the worker
  external_service.track(event)
rescue => e
  # Optionally log internally
  @logger.warn("Failed to track: #{e.message}")
end
```

### 3. Always Handle TaskUpdateFailure

This is a critical event - task results are lost:

```ruby
def on_task_update_failure(event)
  # Log for debugging
  @logger.fatal("Task result lost: #{event.task_id}")

  # Alert operations team
  PagerDuty.trigger(
    severity: :critical,
    summary: "Task result lost: #{event.task_id}"
  )

  # Optionally store for manual recovery
  FailedTaskStore.save(event.task_result)
end
```

### 4. Use Multiple Interceptors

Separate concerns into different interceptors:

```ruby
handler = Conductor::Worker::TaskHandler.new(
  configuration: config,
  event_listeners: [
    MetricsCollector.new(backend: :prometheus),  # Metrics
    StructuredLoggingInterceptor.new,            # Logging
    SentryInterceptor.new,                       # Error tracking
    SLAMonitor.new(thresholds: sla_config),      # SLA monitoring
    AuditLogger.new(log_file: 'audit.log')       # Compliance
  ]
)
```

### 5. Test Your Interceptors

Write tests for your interceptors:

```ruby
RSpec.describe SentryInterceptor do
  let(:interceptor) { described_class.new }

  describe '#on_task_execution_failure' do
    it 'captures exception in Sentry' do
      event = Conductor::Worker::Events::TaskExecutionFailure.new(
        task_type: 'my_task',
        task_id: 'task-123',
        worker_id: 'worker-1',
        workflow_instance_id: 'workflow-456',
        duration_ms: 100,
        cause: StandardError.new('Test error'),
        is_retryable: true
      )

      expect(Sentry).to receive(:capture_exception)
      interceptor.on_task_execution_failure(event)
    end
  end
end
```

---

## Reference

### Event Classes

All events are in the `Conductor::Worker::Events` namespace:

- `Conductor::Worker::Events::PollStarted`
- `Conductor::Worker::Events::PollCompleted`
- `Conductor::Worker::Events::PollFailure`
- `Conductor::Worker::Events::TaskExecutionStarted`
- `Conductor::Worker::Events::TaskExecutionCompleted`
- `Conductor::Worker::Events::TaskExecutionFailure`
- `Conductor::Worker::Events::TaskUpdateFailure`

### Telemetry Classes

- `Conductor::Worker::Telemetry::MetricsCollector` - Event listener that collects metrics
- `Conductor::Worker::Telemetry::NullBackend` - No-op metrics backend
- `Conductor::Worker::Telemetry::PrometheusBackend` - Prometheus metrics backend
- `Conductor::Worker::Telemetry::MetricsServer` - HTTP server for `/metrics` endpoint

### Registration Methods

Register interceptors via `TaskHandler`:

```ruby
handler = Conductor::Worker::TaskHandler.new(
  configuration: config,
  event_listeners: [listener1, listener2]
)
```

Or register manually with the event dispatcher:

```ruby
dispatcher = handler.event_dispatcher
dispatcher.register(Conductor::Worker::Events::PollStarted, ->(event) { puts event })
```
