# Event-Driven Interceptor System - Design Document

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Core Components](#core-components)
4. [Event Hierarchy](#event-hierarchy)
5. [Event Dispatcher](#event-dispatcher)
6. [Listener Protocol](#listener-protocol)
7. [Listener Registration](#listener-registration)
8. [Metrics Collection](#metrics-collection)
9. [Prometheus Integration](#prometheus-integration)
10. [Usage Examples](#usage-examples)
11. [Advanced Use Cases](#advanced-use-cases)
12. [Performance Considerations](#performance-considerations)
13. [File Structure](#file-structure)

---

## Overview

### Purpose

The Event-Driven Interceptor System provides a decoupled, extensible mechanism for observing and reacting to task execution lifecycle events in the Conductor Ruby SDK. This enables:

- **Metrics Collection** - Track poll times, execution durations, error rates
- **Custom Interceptors** - Add logging, tracing, auditing without modifying core code
- **SLA Monitoring** - Alert on tasks exceeding thresholds
- **Cost Tracking** - Monitor compute costs per task type
- **Error Tracking** - Send failures to external services (Sentry, Bugsnag, etc.)

### Design Goals

| Goal | Description |
|------|-------------|
| **Decoupled** | Event publishing is separate from event handling |
| **Thread-Safe** | Safe for concurrent task execution |
| **Extensible** | Add listeners without modifying SDK code |
| **Non-Blocking** | Listener failures never block worker execution |
| **Type-Safe** | Clear event contracts with documented attributes |
| **Pluggable** | Multiple metrics backends (null, Prometheus, custom) |

### Non-Goals

- **Distributed Tracing** - OpenTelemetry integration is a separate concern
- **Built-in Dashboards** - Users provide their own visualization
- **Async Dispatch** - Events are dispatched synchronously for simplicity

---

## Architecture

### High-Level Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Task Execution Layer                              │
│  ┌──────────────────┐           ┌──────────────────┐                    │
│  │    TaskRunner    │           │   TaskHandler    │                    │
│  │  (polling loop)  │           │  (orchestrator)  │                    │
│  └────────┬─────────┘           └────────┬─────────┘                    │
│           │ publish()                    │ register()                   │
└───────────┼──────────────────────────────┼──────────────────────────────┘
            │                              │
            ▼                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        Event Dispatch Layer                              │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                    SyncEventDispatcher                              │ │
│  │  • Thread-safe listener registration (Mutex)                       │ │
│  │  • Synchronous event dispatch                                      │ │
│  │  • Error isolation (listener failures logged, not propagated)      │ │
│  │  • Type-based routing (event.class → listeners)                    │ │
│  └──────────────────────────┬─────────────────────────────────────────┘ │
│                              │ dispatch                                  │
└──────────────────────────────┼──────────────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────────────┐
│                       Listener/Consumer Layer                            │
│  ┌────────────────┐  ┌────────────────┐  ┌─────────────────────────┐    │
│  │MetricsCollector│  │ CustomListener │  │   SLA Monitor           │    │
│  │  (Prometheus)  │  │   (Logging)    │  │   (Alerting)            │    │
│  └────────────────┘  └────────────────┘  └─────────────────────────┘    │
│  ┌────────────────┐  ┌────────────────┐  ┌─────────────────────────┐    │
│  │  Audit Logger  │  │  Cost Tracker  │  │   Error Reporter        │    │
│  │  (Compliance)  │  │   (FinOps)     │  │   (Sentry/Bugsnag)      │    │
│  └────────────────┘  └────────────────┘  └─────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

### Component Interaction Flow

```
TaskRunner                  SyncEventDispatcher              Listeners
    │                              │                            │
    │  publish(PollStarted)        │                            │
    │─────────────────────────────>│                            │
    │                              │  call(event) ──────────────>│ MetricsCollector
    │                              │  call(event) ──────────────>│ CustomListener
    │                              │<───────────────────────────│
    │<─────────────────────────────│                            │
    │                              │                            │
    │  (execute task)              │                            │
    │                              │                            │
    │  publish(TaskExecutionCompleted)                          │
    │─────────────────────────────>│                            │
    │                              │  call(event) ──────────────>│ MetricsCollector
    │                              │  call(event) ──────────────>│ CustomListener
    │                              │<───────────────────────────│
    │<─────────────────────────────│                            │
```

---

## Core Components

### Component Summary

| Component | Location | Purpose |
|-----------|----------|---------|
| `ConductorEvent` | `events/conductor_event.rb` | Base event class with timestamp |
| `TaskRunnerEvent` | `events/conductor_event.rb` | Base for task runner events |
| `PollStarted`, etc. | `events/task_runner_events.rb` | Specific event types |
| `SyncEventDispatcher` | `events/sync_event_dispatcher.rb` | Thread-safe event router |
| `TaskRunnerEventsListener` | `events/listeners.rb` | Listener protocol (duck typing) |
| `ListenerRegistry` | `events/listener_registry.rb` | Bulk listener registration |
| `MetricsCollector` | `telemetry/metrics_collector.rb` | Event-based metrics |
| `PrometheusBackend` | `telemetry/prometheus_backend.rb` | Prometheus integration |
| `NullBackend` | `telemetry/metrics_collector.rb` | No-op backend |

---

## Event Hierarchy

### Class Hierarchy

```
ConductorEvent                    # Base - provides timestamp
└── TaskRunnerEvent               # Base for task runner - adds task_type
    ├── PollStarted               # Polling started
    ├── PollCompleted             # Polling completed successfully
    ├── PollFailure               # Polling failed
    ├── TaskExecutionStarted      # Task execution started
    ├── TaskExecutionCompleted    # Task execution completed
    ├── TaskExecutionFailure      # Task execution failed
    └── TaskUpdateFailure         # Task result update failed (CRITICAL)
```

### Event Attributes

#### ConductorEvent (Base)

```ruby
class ConductorEvent
  attr_reader :timestamp  # Time - UTC timestamp when event was created

  def to_h
    { timestamp: @timestamp.iso8601(3) }
  end
end
```

#### TaskRunnerEvent (Base)

```ruby
class TaskRunnerEvent < ConductorEvent
  attr_reader :task_type  # String - Task definition name
end
```

#### PollStarted

Published when polling starts for a task type.

| Attribute | Type | Description |
|-----------|------|-------------|
| `task_type` | String | Task definition name |
| `worker_id` | String | Unique worker identifier |
| `poll_count` | Integer | Number of polls performed so far |

#### PollCompleted

Published when polling completes successfully.

| Attribute | Type | Description |
|-----------|------|-------------|
| `task_type` | String | Task definition name |
| `duration_ms` | Float | Duration of poll in milliseconds |
| `tasks_received` | Integer | Number of tasks received |

#### PollFailure

Published when polling fails.

| Attribute | Type | Description |
|-----------|------|-------------|
| `task_type` | String | Task definition name |
| `duration_ms` | Float | Duration of poll in milliseconds |
| `cause` | Exception | The exception that caused the failure |

#### TaskExecutionStarted

Published when task execution starts.

| Attribute | Type | Description |
|-----------|------|-------------|
| `task_type` | String | Task definition name |
| `task_id` | String | Unique task identifier |
| `worker_id` | String | Unique worker identifier |
| `workflow_instance_id` | String | Workflow instance identifier |

#### TaskExecutionCompleted

Published when task execution completes successfully.

| Attribute | Type | Description |
|-----------|------|-------------|
| `task_type` | String | Task definition name |
| `task_id` | String | Unique task identifier |
| `worker_id` | String | Unique worker identifier |
| `workflow_instance_id` | String | Workflow instance identifier |
| `duration_ms` | Float | Duration of execution in milliseconds |
| `output_size_bytes` | Integer | Size of output data in bytes (optional) |

#### TaskExecutionFailure

Published when task execution fails.

| Attribute | Type | Description |
|-----------|------|-------------|
| `task_type` | String | Task definition name |
| `task_id` | String | Unique task identifier |
| `worker_id` | String | Unique worker identifier |
| `workflow_instance_id` | String | Workflow instance identifier |
| `duration_ms` | Float | Duration of execution in milliseconds |
| `cause` | Exception | The exception that caused the failure |
| `is_retryable` | Boolean | Whether the error is retryable |

#### TaskUpdateFailure (CRITICAL)

Published when task result update fails after all retries. This is a **critical** event - the task result is lost.

| Attribute | Type | Description |
|-----------|------|-------------|
| `task_type` | String | Task definition name |
| `task_id` | String | Unique task identifier |
| `worker_id` | String | Unique worker identifier |
| `workflow_instance_id` | String | Workflow instance identifier |
| `cause` | Exception | The exception that caused the failure |
| `retry_count` | Integer | Number of retry attempts made |
| `task_result` | TaskResult | The task result that failed to update (for recovery) |

---

## Event Dispatcher

### SyncEventDispatcher

The `SyncEventDispatcher` is a thread-safe, synchronous event dispatcher that routes events to registered listeners.

```ruby
module Conductor::Worker::Events
  class SyncEventDispatcher
    def initialize
      @listeners = Hash.new { |h, k| h[k] = [] }
      @mutex = Mutex.new
    end

    # Register a listener for an event type
    # @param event_type [Class] Event class to listen for
    # @param listener [Proc, #call] Callable to invoke when event is published
    # @return [self]
    def register(event_type, listener)
      @mutex.synchronize do
        @listeners[event_type] << listener unless @listeners[event_type].include?(listener)
      end
      self
    end

    # Unregister a listener for an event type
    # @param event_type [Class] Event class
    # @param listener [Proc, #call] Listener to remove
    # @return [self]
    def unregister(event_type, listener)
      @mutex.synchronize do
        @listeners[event_type].delete(listener)
      end
      self
    end

    # Publish an event to all registered listeners
    # @param event [ConductorEvent] Event to publish
    # @return [self]
    def publish(event)
      listeners = @mutex.synchronize { @listeners[event.class].dup }

      listeners.each do |listener|
        listener.call(event)
      rescue StandardError => e
        # Listener failure is isolated - never breaks the worker
        warn "[Conductor] Event listener error for #{event.class}: #{e.message}"
      end

      self
    end

    # Check if there are listeners registered for an event type
    def has_listeners?(event_type)
      @mutex.synchronize { @listeners[event_type].any? }
    end

    # Get the number of listeners for an event type
    def listener_count(event_type)
      @mutex.synchronize { @listeners[event_type].size }
    end

    # Clear all listeners
    def clear
      @mutex.synchronize { @listeners.clear }
      self
    end
  end
end
```

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Synchronous dispatch** | Simpler than async, avoids ordering issues |
| **Mutex for thread safety** | Protects listener list during registration and iteration |
| **Copy listeners before dispatch** | Allows modification during dispatch without deadlock |
| **Error isolation** | Listener exceptions are logged but don't propagate |
| **Type-based routing** | Events routed by class, not inheritance hierarchy |

### Thread Safety Guarantees

1. **Registration is thread-safe** - Multiple threads can register listeners concurrently
2. **Publishing is thread-safe** - Multiple threads can publish events concurrently
3. **Listeners are called sequentially** - Within a single publish call
4. **Listener exceptions are isolated** - One listener failure doesn't affect others

---

## Listener Protocol

### TaskRunnerEventsListener

The listener protocol uses duck typing - implement only the methods you need:

```ruby
module Conductor::Worker::Events
  # Listener protocol for task runner events
  # Include this module to document the expected interface
  # All methods are optional - implement only the ones you need
  module TaskRunnerEventsListener
    # Called when polling starts
    # @param event [PollStarted]
    def on_poll_started(event); end

    # Called when polling completes successfully
    # @param event [PollCompleted]
    def on_poll_completed(event); end

    # Called when polling fails
    # @param event [PollFailure]
    def on_poll_failure(event); end

    # Called when task execution starts
    # @param event [TaskExecutionStarted]
    def on_task_execution_started(event); end

    # Called when task execution completes successfully
    # @param event [TaskExecutionCompleted]
    def on_task_execution_completed(event); end

    # Called when task execution fails
    # @param event [TaskExecutionFailure]
    def on_task_execution_failure(event); end

    # Called when task update fails after all retries (CRITICAL)
    # @param event [TaskUpdateFailure]
    def on_task_update_failure(event); end
  end
end
```

### Implementation Example

```ruby
class MyListener
  # Only implement the methods you care about
  def on_task_execution_completed(event)
    puts "Task #{event.task_id} completed in #{event.duration_ms}ms"
  end

  def on_task_execution_failure(event)
    puts "Task #{event.task_id} FAILED: #{event.cause.message}"
  end
end
```

---

## Listener Registration

### ListenerRegistry

The `ListenerRegistry` provides bulk registration of listener objects:

```ruby
module Conductor::Worker::Events
  class ListenerRegistry
    # Mapping of event classes to listener method names
    EVENT_METHOD_MAP = {
      PollStarted => :on_poll_started,
      PollCompleted => :on_poll_completed,
      PollFailure => :on_poll_failure,
      TaskExecutionStarted => :on_task_execution_started,
      TaskExecutionCompleted => :on_task_execution_completed,
      TaskExecutionFailure => :on_task_execution_failure,
      TaskUpdateFailure => :on_task_update_failure
    }.freeze

    # Register a listener object with the dispatcher
    # Auto-detects implemented methods via respond_to?
    # @param listener [Object] Object implementing TaskRunnerEventsListener methods
    # @param dispatcher [SyncEventDispatcher] Event dispatcher
    def self.register_task_runner_listener(listener, dispatcher)
      EVENT_METHOD_MAP.each do |event_class, method_name|
        if listener.respond_to?(method_name)
          dispatcher.register(event_class, ->(event) { listener.send(method_name, event) })
        end
      end
    end

    # Register multiple listeners with the dispatcher
    # @param listeners [Array<Object>] Array of listener objects
    # @param dispatcher [SyncEventDispatcher] Event dispatcher
    def self.register_all(listeners, dispatcher)
      listeners.each do |listener|
        register_task_runner_listener(listener, dispatcher)
      end
    end
  end
end
```

### Usage in TaskHandler

```ruby
handler = Conductor::Worker::TaskHandler.new(
  configuration: config,
  event_listeners: [MyListener.new, AnotherListener.new]
)
```

---

## Metrics Collection

### MetricsCollector

The `MetricsCollector` implements `TaskRunnerEventsListener` to collect metrics:

```ruby
module Conductor::Worker::Telemetry
  class MetricsCollector
    include Events::TaskRunnerEventsListener

    def initialize(backend: :null)
      @backend = load_backend(backend)
    end

    def on_poll_started(event)
      @backend.increment('task_poll_total', labels: { task_type: event.task_type })
    end

    def on_poll_completed(event)
      @backend.observe('task_poll_time_seconds', event.duration_ms / 1000.0,
                       labels: { task_type: event.task_type })
    end

    def on_poll_failure(event)
      @backend.increment('task_poll_error_total',
                         labels: {
                           task_type: event.task_type,
                           error: event.cause.class.name
                         })
    end

    def on_task_execution_completed(event)
      @backend.observe('task_execute_time_seconds', event.duration_ms / 1000.0,
                       labels: { task_type: event.task_type })

      return unless event.output_size_bytes

      @backend.observe('task_result_size_bytes', event.output_size_bytes,
                       labels: { task_type: event.task_type })
    end

    def on_task_execution_failure(event)
      @backend.increment('task_execute_error_total',
                         labels: {
                           task_type: event.task_type,
                           exception: event.cause.class.name,
                           retryable: event.is_retryable.to_s
                         })
    end

    def on_task_update_failure(event)
      @backend.increment('task_update_failed_total',
                         labels: { task_type: event.task_type })
    end
  end
end
```

### Backend Protocol

Metrics backends must implement these methods:

```ruby
# Increment a counter
# @param name [String] Metric name
# @param labels [Hash] Metric labels
def increment(name, labels: {})
end

# Observe a value (histogram)
# @param name [String] Metric name
# @param value [Numeric] Value to observe
# @param labels [Hash] Metric labels
def observe(name, value, labels: {})
end

# Set a gauge value
# @param name [String] Metric name
# @param value [Numeric] Value to set
# @param labels [Hash] Metric labels
def set(name, value, labels: {})
end
```

### NullBackend

A no-op backend for when metrics are disabled:

```ruby
class NullBackend
  def increment(name, labels: {}); end
  def observe(name, value, labels: {}); end
  def set(name, value, labels: {}); end
end
```

---

## Prometheus Integration

### PrometheusBackend

The `PrometheusBackend` integrates with the `prometheus-client` gem:

```ruby
module Conductor::Worker::Telemetry
  class PrometheusBackend
    # Default histogram buckets for time measurements (in seconds)
    TIME_BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10].freeze

    # Default histogram buckets for size measurements (in bytes)
    SIZE_BUCKETS = [100, 1000, 10_000, 100_000, 1_000_000, 10_000_000].freeze

    def initialize(registry: nil)
      require 'prometheus/client'
      @registry = registry || Prometheus::Client.registry
      setup_metrics
    end

    def increment(name, labels: {}, value: 1)
      metric = get_or_create_counter(name)
      metric.increment(labels: normalize_labels(labels), by: value)
    end

    def observe(name, value, labels: {})
      metric = get_or_create_histogram(name)
      metric.observe(value, labels: normalize_labels(labels))
    end

    def set(name, value, labels: {})
      metric = get_or_create_gauge(name)
      metric.set(value, labels: normalize_labels(labels))
    end
  end
end
```

### Prometheus Metrics

| Metric Name | Type | Labels | Description |
|-------------|------|--------|-------------|
| `task_poll_total` | Counter | `task_type` | Total number of poll operations |
| `task_poll_time_seconds` | Histogram | `task_type` | Poll latency in seconds |
| `task_poll_error_total` | Counter | `task_type`, `error` | Total poll failures |
| `task_execute_time_seconds` | Histogram | `task_type` | Task execution time in seconds |
| `task_execute_error_total` | Counter | `task_type`, `exception`, `retryable` | Total execution failures |
| `task_result_size_bytes` | Histogram | `task_type` | Task output size in bytes |
| `task_update_failed_total` | Counter | `task_type` | **CRITICAL**: Failed task updates |

### MetricsServer

An optional HTTP server for exposing Prometheus metrics:

```ruby
module Conductor::Worker::Telemetry
  class MetricsServer
    DEFAULT_PORT = 9090

    def initialize(port: DEFAULT_PORT, registry: nil)
      @port = port
      @registry = registry || Prometheus::Client.registry
    end

    def start
      require 'webrick'
      @server = WEBrick::HTTPServer.new(Port: @port, Logger: WEBrick::Log.new('/dev/null'))

      @server.mount_proc '/metrics' do |_req, res|
        res.content_type = 'text/plain; version=0.0.4'
        res.body = Prometheus::Client::Formats::Text.marshal(@registry)
      end

      @server.mount_proc '/health' do |_req, res|
        res.body = '{"status":"healthy"}'
      end

      @thread = Thread.new { @server.start }
    end

    def stop
      @server&.shutdown
      @thread&.join(5)
    end
  end
end
```

---

## Usage Examples

### Basic Metrics Collection

```ruby
require 'conductor'

# Create configuration
config = Conductor::Configuration.new(
  server_api_url: 'https://conductor.example.com/api',
  key_id: 'key',
  key_secret: 'secret'
)

# Create metrics collector with Prometheus backend
metrics = Conductor::Worker::Telemetry::MetricsCollector.new(backend: :prometheus)

# Start metrics server
metrics_server = Conductor::Worker::Telemetry::MetricsServer.new(port: 9090)
metrics_server.start

# Create task handler with metrics
handler = Conductor::Worker::TaskHandler.new(
  configuration: config,
  event_listeners: [metrics]
)

# Start workers
handler.start
handler.join
```

### Custom Logging Interceptor

```ruby
class LoggingInterceptor
  def initialize(logger = Logger.new($stdout))
    @logger = logger
  end

  def on_poll_started(event)
    @logger.debug("Polling for #{event.task_type}...")
  end

  def on_poll_completed(event)
    @logger.debug("Poll for #{event.task_type}: #{event.tasks_received} tasks in #{event.duration_ms}ms")
  end

  def on_task_execution_started(event)
    @logger.info("Starting task #{event.task_id} (#{event.task_type})")
  end

  def on_task_execution_completed(event)
    @logger.info("Completed task #{event.task_id} in #{event.duration_ms}ms")
  end

  def on_task_execution_failure(event)
    @logger.error("Task #{event.task_id} FAILED: #{event.cause.message}")
    @logger.error(event.cause.backtrace.first(5).join("\n"))
  end

  def on_task_update_failure(event)
    @logger.fatal("CRITICAL: Task #{event.task_id} result LOST after #{event.retry_count} retries!")
  end
end

# Use with TaskHandler
handler = Conductor::Worker::TaskHandler.new(
  configuration: config,
  event_listeners: [LoggingInterceptor.new]
)
```

### Error Tracking (Sentry Integration)

```ruby
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
      "CRITICAL: Task result lost",
      level: :fatal,
      extra: {
        task_id: event.task_id,
        task_type: event.task_type,
        retry_count: event.retry_count
      }
    )
  end
end
```

### Multiple Listeners

```ruby
# Combine metrics, logging, and error tracking
handler = Conductor::Worker::TaskHandler.new(
  configuration: config,
  event_listeners: [
    Conductor::Worker::Telemetry::MetricsCollector.new(backend: :prometheus),
    LoggingInterceptor.new,
    SentryInterceptor.new
  ]
)
```

---

## Advanced Use Cases

### SLA Monitor

Monitor task execution times and alert on SLA violations:

```ruby
class SLAMonitor
  def initialize(thresholds:, alerter:)
    @thresholds = thresholds  # { 'task_type' => max_duration_ms }
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
    'process_order' => 5000,    # 5 seconds
    'send_email' => 2000,       # 2 seconds
    'generate_report' => 30000  # 30 seconds
  },
  alerter: SlackAlerter.new(webhook_url: ENV['SLACK_WEBHOOK'])
)
```

### Cost Tracker

Track compute costs per task type:

```ruby
class CostTracker
  def initialize(cost_per_ms:, reporting_interval: 60)
    @cost_per_ms = cost_per_ms  # { 'task_type' => cost_per_ms }
    @costs = Hash.new(0.0)
    @mutex = Mutex.new
    @reporting_interval = reporting_interval
    start_reporting_thread
  end

  def on_task_execution_completed(event)
    cost = (@cost_per_ms[event.task_type] || 0.0001) * event.duration_ms
    @mutex.synchronize { @costs[event.task_type] += cost }
  end

  private

  def start_reporting_thread
    Thread.new do
      loop do
        sleep @reporting_interval
        report_costs
      end
    end
  end

  def report_costs
    @mutex.synchronize do
      total = @costs.values.sum
      puts "Cost Report: Total=$#{format('%.4f', total)}"
      @costs.each { |task_type, cost| puts "  #{task_type}: $#{format('%.4f', cost)}" }
      @costs.clear
    end
  end
end
```

### Audit Logger

Log all task executions for compliance:

```ruby
class AuditLogger
  def initialize(log_file:)
    @logger = Logger.new(log_file)
  end

  def on_task_execution_started(event)
    log_entry('STARTED', event)
  end

  def on_task_execution_completed(event)
    log_entry('COMPLETED', event, duration_ms: event.duration_ms)
  end

  def on_task_execution_failure(event)
    log_entry('FAILED', event,
              duration_ms: event.duration_ms,
              error: event.cause.class.name,
              message: event.cause.message,
              retryable: event.is_retryable)
  end

  private

  def log_entry(status, event, extra = {})
    @logger.info({
      timestamp: event.timestamp.iso8601(3),
      status: status,
      task_type: event.task_type,
      task_id: event.task_id,
      worker_id: event.worker_id,
      workflow_instance_id: event.workflow_instance_id,
      **extra
    }.to_json)
  end
end
```

---

## Performance Considerations

### Event Publishing Overhead

Event publishing is synchronous but lightweight:

1. **Mutex acquisition** - ~100ns on uncontended lock
2. **List copy** - O(n) where n = number of listeners (typically 1-5)
3. **Listener calls** - Dependent on listener implementation

**Typical overhead**: < 1ms per event with 3 listeners

### Recommendations

| Concern | Recommendation |
|---------|----------------|
| **Many listeners** | Keep listener count low (< 10) |
| **Slow listeners** | Offload heavy work to background threads |
| **High-frequency events** | Consider sampling in custom listeners |
| **Logging** | Use async logging (Logger with queue) |
| **Metrics** | Prometheus client is thread-safe and efficient |

### Thread Pool Sizing

The event system doesn't use a separate thread pool. Events are processed in the TaskRunner thread. This means:

- **Listener execution time** directly impacts polling interval
- **Blocking operations** in listeners will block task polling
- **Keep listeners fast** (< 10ms) or offload to background

### Error Isolation Example

```ruby
# If listener A fails, listener B still runs
class FailingListener
  def on_task_execution_completed(event)
    raise "Intentional failure"  # This is caught and logged
  end
end

class WorkingListener
  def on_task_execution_completed(event)
    puts "Still runs!"  # This executes even if FailingListener fails
  end
end
```

---

## File Structure

```
lib/conductor/worker/
├── events/
│   ├── conductor_event.rb         # Base event class + TaskRunnerEvent
│   ├── task_runner_events.rb      # All task runner event types
│   ├── sync_event_dispatcher.rb   # Thread-safe event dispatcher
│   ├── listeners.rb               # TaskRunnerEventsListener protocol
│   └── listener_registry.rb       # Bulk listener registration helper
├── telemetry/
│   ├── metrics_collector.rb       # MetricsCollector + NullBackend
│   └── prometheus_backend.rb      # PrometheusBackend + MetricsServer
├── task_runner.rb                 # Publishes events during polling/execution
└── task_handler.rb                # Creates dispatcher, registers listeners

spec/conductor/worker/
├── events/
│   ├── conductor_event_spec.rb
│   ├── task_runner_events_spec.rb
│   ├── sync_event_dispatcher_spec.rb
│   └── listener_registry_spec.rb
└── telemetry/
    ├── metrics_collector_spec.rb
    └── prometheus_backend_spec.rb
```

---

## Comparison to Python SDK

| Aspect | Python SDK | Ruby SDK |
|--------|------------|----------|
| **Dispatch model** | Async (asyncio.create_task) | Sync (same thread) |
| **Thread safety** | asyncio.Lock | Mutex |
| **Listener protocol** | typing.Protocol | Duck typing (respond_to?) |
| **Event classes** | @dataclass(frozen=True) | attr_reader + to_h |
| **Metrics backend** | Prometheus multiprocess | Prometheus single process |
| **Error isolation** | ✅ Caught and logged | ✅ Caught and logged |
| **Event types** | Same 7 event types | Same 7 event types |

### Why Synchronous in Ruby?

The Python SDK uses async dispatch because:
1. Python uses asyncio for workers
2. Async dispatch avoids blocking the event loop

The Ruby SDK uses synchronous dispatch because:
1. Ruby workers use threads (GVL releases on I/O)
2. Simpler implementation with predictable ordering
3. Listeners typically complete in < 1ms
4. Thread-per-worker model already provides isolation
