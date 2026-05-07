# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Metrics harmonization** - canonical metric surface aligned with the cross-SDK catalog, opt-in via `WORKER_CANONICAL_METRICS=true`
  - New `Conductor::Worker::Telemetry::CanonicalMetricsCollector` and `CanonicalPrometheusBackend` emit the harmonized cross-SDK catalog: counters (`task_poll_total`, `task_execution_started_total`, `task_poll_error_total{exception}`, `task_execute_error_total{exception}`, `task_update_error_total{exception}`, `task_paused_total`, `thread_uncaught_exceptions_total{exception}`, `workflow_start_error_total{workflowType,exception}`), histograms (`task_poll_time_seconds{taskType,status}`, `task_execute_time_seconds`, `task_update_time_seconds`, `http_api_client_request_seconds{method,uri,status}`, `task_result_size_bytes`, `workflow_input_size_bytes{workflowType,version}`), and an `active_workers{taskType}` gauge. Time buckets `0.001…10s`; size buckets `100…10_000_000` bytes; labels are camelCase.
  - `MetricsCollector.create(backend:)` factory selects `LegacyMetricsCollector` (default) or `CanonicalMetricsCollector` based on `WORKER_CANONICAL_METRICS` (truthy: `true`, `1`, `yes`, case-insensitive). `WORKER_LEGACY_METRICS` is reserved for a future default-flip phase.
  - New event types: `HttpApiRequest`, `WorkflowStartError`, `WorkflowInputSize`, `TaskUpdateCompleted`, `TaskPaused`, `ThreadUncaughtException`, `ActiveWorkersChanged`. `RestClient` emits `HttpApiRequest` via a new process-wide `GlobalDispatcher`; `WorkflowExecutor` emits workflow events; `TaskRunner` emits the new task-runner events.
  - Harness manifest sets `WORKER_CANONICAL_METRICS=true`; `harness/main.rb` logs which collector is active.

### Changed

- **BREAKING: Workflow DSL Redesign** - Complete redesign of the workflow DSL for Ruby-idiomatic syntax
  - New entry point: `Conductor.workflow :name do...end` instead of `ConductorWorkflow.new`
  - Block-based workflow definition with method chaining
  - Output references using `task[:field]` syntax instead of `task.output('field')`
  - Input references using `wf[:param]` syntax instead of `workflow.input('param')`
  - Control flow blocks: `parallel do`, `decide expr do`, `loop_over items do`
  - Auto-generated task reference names
  - Simplified LLM task methods with hash-to-ChatMessage auto-conversion

- **Metrics harmonization** - defaults preserved; legacy metrics emit unchanged when `WORKER_CANONICAL_METRICS` is unset
  - Constructor convention changed from `MetricsCollector.new(...)` to `MetricsCollector.create(...)`. The previously released collector behavior is preserved as `LegacyMetricsCollector` and remains the default.
  - Default behavior is unchanged: with no env var set, the metric names and snake_case label conventions (e.g. `task_type`, `error`, `retryable`) shipped in 0.1.0 are preserved.
  - Rewrote `docs/METRICS_AND_INTERCEPTORS.md` (+362 net lines) with Legacy and Canonical Modes section, both catalogs, metrics-not-applicable-to-Ruby table, label table, and a legacy → canonical migration mapping.
  - Updated `docs/design/EVENT_INTERCEPTOR_SYSTEM.md`, `docs/design/WORKER_DESIGN.md`, and `AGENTS.md` to reference the factory and gate.

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
