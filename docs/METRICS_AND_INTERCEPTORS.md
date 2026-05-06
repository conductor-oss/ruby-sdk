# Metrics and Interceptors Guide

The Conductor Ruby SDK can expose Prometheus metrics for worker polling, task
execution, task result updates, payload sizes, workflow starts, and HTTP API
client latency. It also provides an event-driven interceptor system for custom
logging, error tracking, and observability.

This document covers the Ruby SDK metrics emitted by `MetricsCollector.create`,
`LegacyMetricsCollector`, and `CanonicalMetricsCollector`. It does not cover
Conductor server metrics or metrics emitted by other SDKs.

## Table of Contents

- [Legacy and Canonical Modes](#legacy-and-canonical-modes)
- [Quick Start](#quick-start)
- [Canonical Metrics Catalog](#canonical-metrics-catalog)
- [Legacy Metrics Catalog](#legacy-metrics-catalog)
- [Metrics Not Applicable to Ruby](#metrics-not-applicable-to-ruby)
- [Labels](#labels)
- [Migration from Legacy to Canonical](#migration-from-legacy-to-canonical)
- [Prometheus Integration](#prometheus-integration)
- [Custom Metrics Backends](#custom-metrics-backends)
- [Troubleshooting](#troubleshooting)
- [Interceptor System](#interceptor-system)
- [Event Types](#event-types)
- [Creating Custom Interceptors](#creating-custom-interceptors)
- [Advanced Use Cases](#advanced-use-cases)
- [Best Practices](#best-practices)
- [Reference](#reference)

---

## Legacy and Canonical Modes

The Ruby SDK currently supports two mutually exclusive metric surfaces:

- **Legacy metrics** are the default. They preserve the original Ruby SDK names
  and labels, including snake_case label keys like `task_type`.
- **Canonical metrics** are opt-in with `WORKER_CANONICAL_METRICS=true`. They
  use the cross-SDK canonical names, labels, units, and Prometheus histogram
  bucket boundaries.

`MetricsCollector.create` reads `WORKER_CANONICAL_METRICS` when the collector
is created:

| Environment variable | Values | Effect |
|---|---|---|
| `WORKER_CANONICAL_METRICS` | `true`, `1`, or `yes` (case-insensitive, surrounding whitespace ignored) | Selects `CanonicalMetricsCollector`. |
| `WORKER_CANONICAL_METRICS` | unset, blank, `false`, `0`, `no`, or any other value | Selects `LegacyMetricsCollector`. |

Only one implementation is active at a time. The SDK does not emit legacy and
canonical metrics simultaneously. Restart workers after changing
`WORKER_CANONICAL_METRICS` so the factory creates the desired collector.

`WORKER_LEGACY_METRICS` is reserved for a future default-flip phase and is not
currently read by the Ruby SDK factory.

---

## Quick Start

### Enabling Metrics (Legacy, Default)

```ruby
require 'conductor'

# MetricsCollector.create checks WORKER_CANONICAL_METRICS and returns
# the appropriate collector. Default (unset) selects legacy metrics.
metrics = Conductor::Worker::Telemetry::MetricsCollector.create(backend: :prometheus)

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

### Enabling Canonical Metrics

Set the environment variable before the worker starts:

```shell
WORKER_CANONICAL_METRICS=true ruby my_worker.rb
```

The same code above will now return a `CanonicalMetricsCollector` instead.

---

## Canonical Metrics Catalog

Canonical timing values are seconds. Canonical size values are bytes. Label
names use camelCase. Metrics are created lazily and appear in `/metrics` only
after the corresponding event records them.

### Canonical Counters

| Metric | Labels | Description |
|---|---|---|
| `task_poll_total` | `taskType` | Incremented each time the worker issues a poll request. |
| `task_execution_started_total` | `taskType` | Incremented when a polled task is dispatched to the worker function. |
| `task_poll_error_total` | `taskType`, `exception` | Incremented when a poll request fails client-side. |
| `task_execute_error_total` | `taskType`, `exception` | Incremented when the worker function throws. |
| `task_update_error_total` | `taskType`, `exception` | Incremented when updating the task result fails. |
| `task_paused_total` | `taskType` | Incremented when a worker is paused and skips acting on a poll. |
| `thread_uncaught_exceptions_total` | `exception` | Incremented when a worker thread raises an uncaught exception. |
| `workflow_start_error_total` | `workflowType`, `exception` | Incremented when starting a workflow fails client-side. |

### Canonical Time Histograms

All canonical time histograms use buckets (in seconds):

```text
0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10
```

| Metric | Labels | Description |
|---|---|---|
| `task_poll_time_seconds` | `taskType`, `status` | Poll request latency. `status` is `SUCCESS` or `FAILURE`. |
| `task_execute_time_seconds` | `taskType`, `status` | Worker function execution duration. `status` is `SUCCESS` or `FAILURE`. |
| `task_update_time_seconds` | `taskType`, `status` | Task-result update latency. `status` is `SUCCESS` or `FAILURE`. |
| `http_api_client_request_seconds` | `method`, `uri`, `status` | HTTP API client request latency. `status` is the HTTP status code as a string, or the exception class name on network failure. |

Each histogram exposes Prometheus series such as:

```prometheus
task_execute_time_seconds_bucket{taskType="my_task",status="SUCCESS",le="0.1"} 42.0
task_execute_time_seconds_count{taskType="my_task",status="SUCCESS"} 50.0
task_execute_time_seconds_sum{taskType="my_task",status="SUCCESS"} 2.3
```

### Canonical Size Histograms

All canonical size histograms use buckets (in bytes):

```text
100, 1000, 10000, 100000, 1000000, 10000000
```

| Metric | Labels | Description |
|---|---|---|
| `task_result_size_bytes` | `taskType` | Serialized task result output size. |
| `workflow_input_size_bytes` | `workflowType`, `version` | Serialized workflow input size. `version` is an empty string when the workflow version is absent. |

### Canonical Gauges

| Metric | Labels | Description |
|---|---|---|
| `active_workers` | `taskType` | Current number of worker threads actively executing tasks. |

---

## Legacy Metrics Catalog

Legacy mode is the default so existing dashboards and alerts continue to work.
Legacy labels use snake_case (`task_type`). Legacy histograms do not carry a
`status` label. Legacy poll failure does not record poll time -- only the error
counter is incremented.

### Legacy Counters

| Metric | Labels | Description |
|---|---|---|
| `task_poll_total` | `task_type` | Incremented each time polling is done. |
| `task_poll_error_total` | `task_type`, `error` | Poll failures. `error` is the exception class name. |
| `task_execute_error_total` | `task_type`, `exception`, `retryable` | Task execution errors. `retryable` is `true` or `false`. |
| `task_update_failed_total` | `task_type` | Failed task result updates (critical -- task result lost). |

### Legacy Time Histograms

Legacy time histograms use buckets (in seconds):

```text
0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10
```

| Metric | Labels | Description |
|---|---|---|
| `task_poll_time_seconds` | `task_type` | Poll request latency. Recorded on successful polls only. |
| `task_execute_time_seconds` | `task_type` | Worker function execution duration. |

### Legacy Size Histograms

| Metric | Labels | Description |
|---|---|---|
| `task_result_size_bytes` | `task_type` | Serialized task result output size. Uses the same bucket set as canonical. |

Legacy mode does not emit `task_execution_started_total`,
`task_update_time_seconds`, `task_paused_total`,
`thread_uncaught_exceptions_total`, `workflow_start_error_total`,
`http_api_client_request_seconds`, `workflow_input_size_bytes`, or
`active_workers`.

---

## Metrics Not Applicable to Ruby

The cross-SDK canonical catalog defines additional metrics that are not
applicable to the Ruby SDK's runtime model:

| Canonical metric | Why N/A for Ruby |
|---|---|
| `task_ack_error_total` | Batch-poll response is the ack; there is no separate ack call. |
| `task_ack_failed_total` | Same reason. |
| `task_execution_queue_full_total` | Ruby uses `fallback_policy: :caller_runs` which back-pressures the polling thread instead of rejecting tasks. |
| `worker_restart_total` | Python-only. Its multi-process supervisor restarts child processes. Ruby uses threads, fibers, or ractors. |
| `external_payload_used_total` | Ruby SDK has no external-payload-storage integration. |

Users cross-referencing the harmonization spec or documentation from other
Conductor SDKs may notice these metrics in other catalogs. Their absence in
the Ruby SDK is intentional.

---

## Labels

| Label | Used by | Values |
|---|---|---|
| `task_type` | Legacy worker metrics | Task definition name. Replaced by `taskType` in canonical mode. |
| `taskType` | Canonical worker metrics | Task definition name. |
| `workflowType` | Canonical workflow metrics | Workflow definition name. |
| `version` | `workflow_input_size_bytes` | Workflow version as a string. Empty string when the version is absent. |
| `status` | Canonical task time metrics | `SUCCESS` or `FAILURE`. For `http_api_client_request_seconds`, the HTTP status code as a string, or the exception class name on failure. |
| `exception` | Canonical error counters | Exception class name, such as `Faraday::TimeoutError`. |
| `error` | Legacy `task_poll_error_total` | Exception class name. Renamed to `exception` in canonical mode. |
| `retryable` | Legacy `task_execute_error_total` | `true` or `false`. Dropped in canonical mode. |
| `method` | HTTP metrics | HTTP verb (`GET`, `POST`, etc.). |
| `uri` | HTTP metrics | Request path from the HTTP client. May contain interpolated identifiers. |

---

## Migration from Legacy to Canonical

Switching to canonical metrics is an explicit metrics-surface cutover. Enable
`WORKER_CANONICAL_METRICS=true` in a lower environment first, then update
dashboards, recording rules, and alerts before enabling it in production.

Key changes:

- Legacy task labels use `task_type`; canonical task labels use `taskType`.
- Legacy poll failure only increments the error counter; canonical also records
  poll time with `status=FAILURE`.
- Legacy execution errors carry an extra `retryable` label; canonical drops it.
- Legacy poll errors use the `error` label; canonical uses `exception`.
- Legacy `task_update_failed_total` becomes `task_update_error_total` with an
  added `exception` label.
- Canonical time histogram buckets start at 0.001s; legacy starts at 0.005s.
- Canonical adds metrics that legacy never emits: `task_execution_started_total`,
  `task_update_time_seconds`, `task_paused_total`,
  `thread_uncaught_exceptions_total`, `workflow_start_error_total`,
  `http_api_client_request_seconds`, `workflow_input_size_bytes`, and
  `active_workers`.
- Canonical and legacy collectors are mutually exclusive. During a migration,
  compare scrape output by running separate worker instances or environments
  with and without `WORKER_CANONICAL_METRICS=true`.

Legacy-to-canonical replacements:

| Legacy metric | Canonical replacement |
|---|---|
| `task_poll_total{task_type}` | `task_poll_total{taskType}` |
| `task_poll_time_seconds{task_type}` | `task_poll_time_seconds{taskType,status}` |
| `task_poll_error_total{task_type,error}` | `task_poll_error_total{taskType,exception}` |
| `task_execute_time_seconds{task_type}` | `task_execute_time_seconds{taskType,status}` |
| `task_execute_error_total{task_type,exception,retryable}` | `task_execute_error_total{taskType,exception}` |
| `task_result_size_bytes{task_type}` | `task_result_size_bytes{taskType}` |
| `task_update_failed_total{task_type}` | `task_update_error_total{taskType,exception}` |

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

metrics = Conductor::Worker::Telemetry::MetricsCollector.create(backend: :prometheus)

metrics_server = Conductor::Worker::Telemetry::MetricsServer.new(port: 9090)
metrics_server.start

handler = Conductor::Worker::TaskHandler.new(
  configuration: config,
  event_listeners: [metrics]
)

handler.start
handler.join

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

registry = Prometheus::Client::Registry.new
backend = Conductor::Worker::Telemetry::PrometheusBackend.new(registry: registry)
metrics = Conductor::Worker::Telemetry::MetricsCollector.create(backend: backend)
```

---

## Custom Metrics Backends

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
metrics = Conductor::Worker::Telemetry::MetricsCollector.create(
  backend: DatadogBackend.new(statsd)
)
```

---

## Troubleshooting

### Metrics Are Empty

- Verify that `MetricsCollector.create` is called and the collector is passed
  to `TaskHandler` via `event_listeners:`.
- Verify workers have polled or executed tasks. Metrics are created lazily when
  the relevant event occurs.
- Confirm the scrape endpoint is reachable at the expected host and port.

### Missing HTTP or Workflow Metrics

- `http_api_client_request_seconds` requires canonical mode. Legacy mode does
  not emit HTTP metrics. The canonical collector auto-subscribes to
  `GlobalDispatcher` for `HttpApiRequest` events from the HTTP layer.
- `workflow_input_size_bytes` and `workflow_start_error_total` require canonical
  mode and only record when the corresponding `WorkflowExecutor` events fire.

### High Cardinality

- Watch the `uri` label on `http_api_client_request_seconds`. The HTTP client
  may include interpolated path identifiers in the request path.
- Prefer canonical mode for bounded `exception` labels using exception class
  names instead of raw error messages.
- Avoid embedding user identifiers or unbounded values in task type, workflow
  type, or other label values.

---

## Interceptor System

The Conductor Ruby SDK provides an event-driven interceptor system that allows
you to:

- **Monitor performance** - Track polling times, execution durations, error rates
- **Implement custom logging** - Add structured logging for task execution
- **Track errors** - Send failures to error tracking services (Sentry, Bugsnag, etc.)
- **Collect metrics** - Export to Prometheus, Datadog, or custom backends
- **Build alerting** - Monitor SLAs and trigger alerts on violations

```
TaskRunner
    │
    │ publishes events
    ▼
SyncEventDispatcher ──────► Listener 1 (MetricsCollector)
                    ──────► Listener 2 (LoggingInterceptor)
                    ──────► Listener 3 (SentryInterceptor)
```

When a worker polls for tasks, executes them, or encounters errors, events are
published to all registered listeners. Listeners can then process these events
independently.

---

## Event Types

The SDK publishes events during worker execution. Any object that responds to
the corresponding `on_*` method can listen for these events.

### Poll Events

| Event | When Published | Key Attributes |
|---|---|---|
| `PollStarted` | Before polling for tasks | `task_type`, `worker_id`, `poll_count` |
| `PollCompleted` | After successful poll | `task_type`, `duration_ms`, `tasks_received` |
| `PollFailure` | When poll fails | `task_type`, `duration_ms`, `cause` |

### Execution Events

| Event | When Published | Key Attributes |
|---|---|---|
| `TaskExecutionStarted` | Before task execution | `task_type`, `task_id`, `worker_id`, `workflow_instance_id` |
| `TaskExecutionCompleted` | After successful execution | `task_type`, `task_id`, `duration_ms`, `output_size_bytes` |
| `TaskExecutionFailure` | When execution fails | `task_type`, `task_id`, `duration_ms`, `cause`, `is_retryable` |

### Update Events

| Event | When Published | Key Attributes |
|---|---|---|
| `TaskUpdateCompleted` | After successful result update | `task_type`, `task_id`, `duration_ms` |
| `TaskUpdateFailure` | When result update fails after all retries | `task_type`, `task_id`, `retry_count`, `task_result`, `cause` |

### Worker State Events

| Event | When Published | Key Attributes |
|---|---|---|
| `TaskPaused` | When a paused worker skips a poll | `task_type` |
| `ThreadUncaughtException` | When a worker thread raises an uncaught exception | `cause` |
| `ActiveWorkersChanged` | When the active worker count changes | `task_type`, `count` |

### Workflow Events

| Event | When Published | Key Attributes |
|---|---|---|
| `WorkflowStartError` | When starting a workflow fails client-side | `workflow_type`, `cause` |
| `WorkflowInputSize` | When a workflow is started | `workflow_type`, `version`, `size_bytes` |

### HTTP Events

| Event | When Published | Key Attributes |
|---|---|---|
| `HttpApiRequest` | After every HTTP API client request | `method`, `uri`, `status`, `duration_ms` |

**Important**: `TaskUpdateFailure` is a critical event indicating that a task
result was lost. You should always handle this event to prevent silent data
loss.

---

## Creating Custom Interceptors

### Basic Structure

An interceptor is any object that responds to one or more `on_*` methods:

```ruby
class MyInterceptor
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
    @cost_per_ms = cost_per_ms
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

Interceptors run synchronously in the worker thread. Keep processing fast to
avoid impacting task execution:

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

Errors in interceptors are caught and logged but don't affect other
interceptors:

```ruby
def on_task_execution_completed(event)
  external_service.track(event)
rescue => e
  @logger.warn("Failed to track: #{e.message}")
end
```

### 3. Always Handle TaskUpdateFailure

This is a critical event -- task results are lost:

```ruby
def on_task_update_failure(event)
  @logger.fatal("Task result lost: #{event.task_id}")
  PagerDuty.trigger(severity: :critical, summary: "Task result lost: #{event.task_id}")
  FailedTaskStore.save(event.task_result)
end
```

### 4. Use Multiple Interceptors

Separate concerns into different interceptors:

```ruby
handler = Conductor::Worker::TaskHandler.new(
  configuration: config,
  event_listeners: [
    Conductor::Worker::Telemetry::MetricsCollector.create(backend: :prometheus),
    StructuredLoggingInterceptor.new,
    SentryInterceptor.new,
    SLAMonitor.new(thresholds: sla_config),
  ]
)
```

### 5. Test Your Interceptors

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

### Telemetry Classes

- `Conductor::Worker::Telemetry::MetricsCollector` - Factory module; `.create` returns the appropriate collector
- `Conductor::Worker::Telemetry::LegacyMetricsCollector` - Pre-harmonization metric set with `task_type` labels
- `Conductor::Worker::Telemetry::CanonicalMetricsCollector` - Canonical metric set with `taskType` labels
- `Conductor::Worker::Telemetry::NullBackend` - No-op metrics backend
- `Conductor::Worker::Telemetry::PrometheusBackend` - Legacy Prometheus backend
- `Conductor::Worker::Telemetry::CanonicalPrometheusBackend` - Canonical Prometheus backend
- `Conductor::Worker::Telemetry::MetricsServer` - WEBrick HTTP server for `/metrics` and `/health` endpoints

### Event Classes

All events are in the `Conductor::Worker::Events` namespace:

- `PollStarted`, `PollCompleted`, `PollFailure`
- `TaskExecutionStarted`, `TaskExecutionCompleted`, `TaskExecutionFailure`
- `TaskUpdateCompleted`, `TaskUpdateFailure`
- `TaskPaused`, `ThreadUncaughtException`, `ActiveWorkersChanged`
- `WorkflowStartError`, `WorkflowInputSize`
- `HttpApiRequest`

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
