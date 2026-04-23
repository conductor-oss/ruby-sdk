# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **SDK Metrics Harmonization (Phase 1)** - Aligned worker telemetry with the
  cross-SDK canonical catalog in
  [`sdk-metrics-harmonization.md`](https://github.com/orkes-io/certification-cloud-util/blob/main/sdk-metrics-harmonization.md).
  New canonical series emitted by `MetricsCollector` + `PrometheusBackend`:
  - Counters: `task_execution_started_total`, `task_update_error_total`,
    `task_paused_total`, `thread_uncaught_exceptions_total`,
    `workflow_start_error_total`
  - Histograms: `task_update_time_seconds{status}`,
    `http_api_client_request_seconds{method, uri, status}`, and a `status` label
    on `task_poll_time_seconds` / `task_execute_time_seconds`
  - Gauges: `task_result_size_bytes` (last-value, replaces histogram shape as
    canonical), `workflow_input_size_bytes`, `active_workers`
- New worker event classes published by the task runners, workflow executor, and
  HTTP client: `TaskUpdateCompleted`, `TaskPaused`, `ThreadUncaughtException`,
  `ActiveWorkersChanged`, `WorkflowStartError`, `WorkflowInputSize`,
  `HttpApiRequest`. `TaskUpdateFailure` gained a `duration_ms` attribute.
- `Conductor::Worker::Events::GlobalDispatcher` - process-wide singleton event
  bus used by the HTTP client so `HttpApiRequest` events reach
  `MetricsCollector` without dependency-injecting a dispatcher through the HTTP
  stack. `MetricsCollector.new` auto-subscribes; pass
  `subscribe_global_http: false` to opt out (e.g. tests).
- Canonical time-histogram buckets now include `0.001s` at the low end to match
  the Java/Go/Python catalog.

### Deprecated

- `task_update_failed_total{task_type}` - retained as a deprecated alias of
  `task_update_error_total` during Phase 1; will be removed in a later release.
- `task_result_size_bytes_histogram{task_type}` - retained as the
  pre-harmonization histogram shape of `task_result_size_bytes` during Phase 1;
  dashboards should migrate to the canonical Gauge named
  `task_result_size_bytes`.

### Changed

- Worker-level metrics now dual-emit the canonical `taskType` (camelCase) label
  alongside the legacy `task_type` label with identical values. Existing
  dashboards continue to resolve while consumers migrate to `taskType`.
- `task_poll_error_total` now dual-emits `exception` (canonical) alongside the
  legacy `error` label.
- `PrometheusBackend` pre-registers every canonical and legacy metric with an
  explicit label set and normalizes caller-supplied labels so partial callers
  never trigger `prometheus-client` label-mismatch errors.
- **BREAKING: Workflow DSL Redesign** - Complete redesign of the workflow DSL for Ruby-idiomatic syntax
  - New entry point: `Conductor.workflow :name do...end` instead of `ConductorWorkflow.new`
  - Block-based workflow definition with method chaining
  - Output references using `task[:field]` syntax instead of `task.output('field')`
  - Input references using `wf[:param]` syntax instead of `workflow.input('param')`
  - Control flow blocks: `parallel do`, `decide expr do`, `loop_over items do`
  - Auto-generated task reference names
  - Simplified LLM task methods with hash-to-ChatMessage auto-conversion

### Removed

- Old DSL classes removed (breaking change):
  - `ConductorWorkflow` - replaced by `Conductor.workflow` entry point
  - `TaskInterface` - replaced by `TaskRef` (internal)
  - Task classes: `SimpleTask`, `SwitchTask`, `ForkTask`, `JoinTask`, `DoWhileTask`, `HttpTask`, `SubWorkflowTask`, `WaitTask`, `TerminateTask`, `SetVariableTask`, `DynamicForkTask`, `JavascriptTask`, `JsonJqTask`, `EventTask`, `HttpPollTask`, `DynamicTask`, `HumanTask`, `StartWorkflowTask`, `KafkaPublishTask`, `WaitForWebhookTask`
  - LLM task classes: `LlmChatCompleteTask`, `LlmTextCompleteTask`, `LlmGenerateEmbeddingsTask`, `LlmIndexTextTask`, `LlmIndexDocumentTask`, `LlmSearchIndexTask`, `LlmQueryEmbeddingsTask`, `LlmStoreEmbeddingsTask`, `LlmSearchEmbeddingsTask`, `GenerateImageTask`, `GenerateAudioTask`, `GetDocumentTask`, `ListMcpToolsTask`, `CallMcpToolTask`

### Migration Guide

**Before (old DSL):**
```ruby
include Conductor::Workflow
workflow = ConductorWorkflow.new(client, 'my_workflow', version: 1)
task = SimpleTask.new('greet', 'greet_ref').input('name', workflow.input('name'))
workflow >> task
workflow.output_parameter('result', task.output('result'))
```

**After (new DSL):**
```ruby
workflow = Conductor.workflow :my_workflow, version: 1, executor: executor do
  task = simple :greet, name: wf[:name]
  output result: task[:result]
end
```

## [0.1.0] - 2026-02-09

### Added

- **Core Infrastructure**
  - Configuration with environment variable support
  - Authentication (token management, TTL refresh, exponential backoff)
  - HTTP Transport using Faraday with retry, connection pooling, SSL support
  - ApiClient with serialization/deserialization and auth injection
  - Exception hierarchy (ApiError, AuthenticationError, etc.)

- **Resource APIs (17 classes)**
  - WorkflowResourceApi - Workflow operations
  - TaskResourceApi - Task operations
  - MetadataResourceApi - Workflow/task definitions
  - SchedulerResourceApi - Schedule management
  - EventResourceApi - Event handlers
  - WorkflowBulkResourceApi - Bulk operations
  - PromptResourceApi - AI prompt management
  - SecretResourceApi - Secret management
  - IntegrationResourceApi - External integrations
  - SchemaResourceApi - JSON schema management
  - AuthorizationResourceApi - Permissions
  - ApplicationResourceApi - Application management
  - UserResourceApi - User management
  - GroupResourceApi - Group management
  - RoleResourceApi - Role management
  - TokenResourceApi - Token operations
  - GatewayAuthResourceApi - Gateway authentication

- **High-Level Clients (9 classes)**
  - WorkflowClient - Workflow operations
  - TaskClient - Task operations
  - MetadataClient - Metadata operations
  - SchedulerClient - Schedule management
  - PromptClient - AI prompts
  - SecretClient - Secrets
  - IntegrationClient - Integrations
  - SchemaClient - Schemas
  - AuthorizationClient - Authorization

- **Worker Framework**
  - Worker module with DSL for task definition
  - Class-based workers using `include Conductor::Worker::WorkerModule`
  - Block-based workers using `Conductor::Worker.define`
  - TaskRunner with multi-threaded polling and execution
  - FiberExecutor for lightweight concurrency
  - RactorTaskRunner for true parallelism (Ruby 3+)
  - Telemetry with Prometheus metrics backend
  - Event system for task lifecycle hooks

- **Workflow DSL (25+ task types)**
  - Control Flow: SimpleTask, SwitchTask, ForkTask, JoinTask, DoWhileTask, DynamicTask, DynamicForkTask, SubWorkflowTask
  - System Tasks: HttpTask, HttpPollTask, EventTask, WaitTask, WaitForWebhookTask, TerminateTask, SetVariableTask, JsonJqTask, JavascriptTask, KafkaPublishTask, StartWorkflowTask, HumanTask
  - LLM/AI Tasks: LlmChatCompleteTask, LlmTextCompleteTask, LlmGenerateEmbeddingsTask, LlmIndexTextTask, LlmIndexDocumentTask, LlmSearchIndexTask, LlmQueryEmbeddingsTask, LlmSearchEmbeddingsTask, LlmStoreEmbeddingsTask, GenerateImageTask, GenerateAudioTask, GetDocumentTask, CallMcpToolTask, ListMcpToolsTask

- **OrkesClients Factory**
  - Single entry point for all client creation
  - WorkflowExecutor for synchronous workflow execution

- **Models (50+ classes)**
  - HTTP models for all API request/response types
  - Orkes-specific models (MetadataTag, RateLimitTag, etc.)

- **Examples**
  - `helloworld/` - Simplest complete example
  - `simple_worker.rb` - Worker implementation patterns
  - `simple_workflow.rb` - Basic workflow client usage
  - `workflow_dsl.rb` - Comprehensive DSL examples
  - `dynamic_workflow.rb` - Runtime workflow creation
  - `kitchensink.rb` - All major task types demo
  - `workflow_ops.rb` - Workflow lifecycle operations

- **Testing**
  - 281 unit tests
  - 110 integration tests covering all major API categories
  - Tests for Scheduler, Events, Bulk Operations, Workflow, Task, Prompt APIs

### Notes

- Full feature parity with Python SDK
- Supports both OSS Conductor and Orkes Cloud
- Ruby 2.6+ compatible (Ruby 3+ recommended for Ractor support)

[0.1.0]: https://github.com/conductor-oss/ruby-sdk/releases/tag/v0.1.0
