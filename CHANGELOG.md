# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
