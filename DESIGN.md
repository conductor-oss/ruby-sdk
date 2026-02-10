# Conductor Ruby SDK - Design Document

## Overview

This SDK is a Ruby port of the [Conductor Python SDK](https://github.com/conductor-sdk/conductor-python), designed to provide a Ruby-native interface to Conductor OSS while maintaining architectural parity with the Python implementation.

## Design Principles

1. **Follow Python SDK architecture** - Maintain the same layers, patterns, and behaviors
2. **Ruby-idiomatic API** - Use Ruby conventions (snake_case, blocks, symbols) while keeping the same capabilities
3. **Feature parity** - Support all features from the Python SDK
4. **Hybrid DSL** - Block-based workflow definition (primary) + operator chaining (secondary)

## Architecture Layers

```
┌─────────────────────────────────────────────────────┐
│          User Code (Workflows + Workers)            │
└─────────────────────────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────┐
│    High-Level DSL                                    │
│    • ConductorWorkflow (block DSL + >> operator)    │
│    • Task types (Simple, Fork, Switch, HTTP, LLM)   │
│    • Worker framework (class/block/method-based)    │
└─────────────────────────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────┐
│    Domain Clients (Facades)                          │
│    • WorkflowClient, TaskClient, MetadataClient      │
│    • WorkflowExecutor                                │
│    • OrkesClients (main facade)                      │
└─────────────────────────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────┐
│    Resource APIs (HTTP endpoints)                    │
│    • TaskResourceApi, WorkflowResourceApi, etc.     │
│    • Direct mapping to Conductor REST API            │
└─────────────────────────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────┐
│    HTTP Transport                                    │
│    • ApiClient (auth, serialization, dispatch)      │
│    • RestClient (Faraday + HTTP/2)                  │
│    • BaseModel (SWAGGER_TYPES pattern)              │
└─────────────────────────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────┐
│    Configuration                                      │
│    • Server URL, auth settings                       │
│    • Token management (class-level cache)            │
└─────────────────────────────────────────────────────┘
```

## Current Implementation Status

### ✅ Phase 1: Foundation (COMPLETED)

- [x] Gem scaffold (`conductor_ruby.gemspec`, `Gemfile`, `Rakefile`)
- [x] RuboCop configuration
- [x] RSpec setup
- [x] `Conductor::VERSION`
- [x] `Conductor::Configuration`
  - Server URL resolution (param > env > default)
  - UI URL derivation
  - Auth settings integration
- [x] `Conductor::Configuration::AuthenticationSettings`
  - Key/secret from params or `ENV`
  - `#configured?` check
- [x] `Conductor::Exceptions`
  - `ConductorError` (base)
  - `ApiError` (HTTP errors)
  - `AuthorizationError` (401/403 with token parsing)
  - `NonRetryableError` (worker terminal failures)
  - `TaskInProgress` (long-running task signaling)

### 🚧 Phase 2: HTTP Layer (NEXT)

- [ ] `Conductor::Http::RestClient` (Faraday-based)
  - HTTP/2 support
  - Connection pooling (100 max, 50 keepalive)
  - Automatic retries (3x)
  - 120s timeout
  - Raise `AuthorizationError` on 401/403
  - Raise `ApiError` on non-2xx
- [ ] `Conductor::Http::BaseModel`
  - `SWAGGER_TYPES` constant (hash of attr => type string)
  - `ATTRIBUTE_MAP` constant (attr => JSON key)
  - `#to_h` (recursive serialization)
  - `.from_hash(hash)` (deserialization with type parsing)
- [ ] `Conductor::Http::ApiClient`
  - **Auth token management:**
    - Initial fetch: POST `/api/token` with `keyId`/`keySecret`
    - 404 on `/token` → disable auth (OSS mode)
    - TTL-based proactive refresh (default 45 min)
    - Retry on 401/403 with `EXPIRED_TOKEN`/`INVALID_TOKEN`
    - Exponential backoff on failures (2^n seconds, max 5 attempts)
  - `#sanitize_for_serialization(obj)` - recursive hash/array/model/datetime
  - `#deserialize(response, type_string)` - parse `'list[Task]'`, `'dict(str, int)'`
  - `#call_api(path, method, opts)` - main dispatch with retry wrapper
- [ ] Core models (60+ classes):
  - `Conductor::Models::Task`
  - `Conductor::Models::TaskResult`
  - `Conductor::Models::TaskResultStatus`
  - `Conductor::Models::Workflow`
  - `Conductor::Models::WorkflowDef`
  - `Conductor::Models::StartWorkflowRequest`
  - ... (see Python SDK `http/models/` for full list)

### 📋 Phase 3: Resource APIs

- [ ] `Conductor::Http::Api::TaskResourceApi` (19 endpoints)
- [ ] `Conductor::Http::Api::WorkflowResourceApi` (21 endpoints)
- [ ] `Conductor::Http::Api::MetadataResourceApi` (13 endpoints)
- [ ] `Conductor::Http::Api::WorkflowBulkResourceApi` (8 endpoints)
- [ ] `Conductor::Http::Api::EventResourceApi` (5 endpoints)
- [ ] Additional Resource APIs (Scheduler, Secret, Authorization, etc.)

### 📋 Phase 4: Domain Clients

- [ ] `Conductor::Client::WorkflowClient` (abstract interface)
- [ ] `Conductor::Client::OrkesWorkflowClient` (implementation)
- [ ] `Conductor::Client::TaskClient` + implementation
- [ ] `Conductor::Client::MetadataClient` + implementation
- [ ] `Conductor::Client::OrkesClients` (facade)
- [ ] `Conductor::WorkflowExecutor`

### 📋 Phase 5: Worker Framework

- [ ] `Conductor::Worker` (mixin module)
- [ ] `Conductor::Worker.define` (block-based workers)
- [ ] `worker_task` class method (class-based workers)
- [ ] `Conductor::TaskContext` (thread-local)
- [ ] `Conductor::TaskResult` (convenience constructors)
- [ ] `Conductor::TaskRunner` (poll-execute-update loop)
- [ ] `Conductor::TaskHandler` (manages multiple workers)

### 📋 Phase 6: Workflow DSL

- [ ] `Conductor::Workflow::ConductorWorkflow` (builder)
- [ ] Block DSL with helper methods (`simple`, `fork`, `switch`, etc.)
- [ ] `>>` operator support
- [ ] `ref(:task_name)` with `method_missing` for output refs
- [ ] `input(:field)` / `output(:field)` helpers
- [ ] Task types:
  - `Conductor::Workflow::Task::Simple`
  - `Conductor::Workflow::Task::Fork` / `Join`
  - `Conductor::Workflow::Task::Switch`
  - `Conductor::Workflow::Task::DoWhile`
  - `Conductor::Workflow::Task::Http`
  - `Conductor::Workflow::Task::SubWorkflow`
  - `Conductor::Workflow::Task::Wait`
  - `Conductor::Workflow::Task::Event`
  - `Conductor::Workflow::Task::Inline`
  - `Conductor::Workflow::Task::JsonJq`
  - `Conductor::Workflow::Task::SetVariable`
  - `Conductor::Workflow::Task::Terminate`
  - LLM tasks (15+ types)

### 📋 Phase 7: Examples & Documentation

- [ ] `examples/simple_worker.rb`
- [ ] `examples/workflow_definition.rb`
- [ ] `examples/workflow_execution.rb`
- [ ] `examples/kitchen_sink.rb`
- [ ] Complete API documentation
- [ ] Usage guides

## Key Implementation Decisions

### Auth Flow (Matches Python SDK Exactly)

| Scenario | Behavior |
|----------|----------|
| No auth configured | Skip auth. No `X-Authorization` header. |
| Initial token fetch | POST `/api/token` → cache token (class-level). |
| `/token` returns 404 | **Disable auth.** Set `auth_configured? = false`. Log "OSS mode". |
| Token TTL expired | Proactively refresh before next request. |
| Server 401/403 with `EXPIRED_TOKEN` | Force-refresh, retry request once. |
| Server 401/403 with `INVALID_TOKEN` | Force-refresh, retry request once. |
| Token refresh fails | Exponential backoff: 2^n seconds, max 5 attempts. |

### Worker Definition Styles

```ruby
# Style 1: Class-based (recommended for complex workers)
class OrderProcessor
  include Conductor::Worker
  worker_task 'process_order', poll_interval: 200, thread_count: 5

  def execute(order_id:, amount: 0.0)
    # Auto-mapped from task.input_data
    { processed: true, order_id: order_id }
  end
end

# Style 2: Block-based (quick workers)
Conductor::Worker.define 'send_email', poll_interval: 100 do |to:, subject:|
  EmailService.deliver(to: to, subject: subject)
  { sent: true }
end

# Style 3: Method annotation (closest to Python @worker_task)
module MyWorkers
  extend Conductor::Worker::Annotatable

  def self.greet(name:)
    { greeting: "Hello #{name}" }
  end
  worker_task :greet, task_definition_name: 'greet_user'
end
```

### Workflow DSL Examples

```ruby
# Block DSL (primary pattern)
workflow = client.workflow 'order_pipeline' do
  simple :validate_order
  simple :process_payment

  http :notify,
    url: ref(:process_payment).callback_url,
    method: :post,
    body: { order_id: input(:order_id) }

  fork [
    [simple(:send_email), simple(:update_crm)],
    [simple(:send_sms)]
  ]

  switch ref(:validate_order).tier, case_value: true do
    on 'gold',   [simple(:apply_discount)]
    on 'silver', [simple(:apply_small_discount)]
    default      [simple(:no_discount)]
  end
end

# Operator chaining (secondary pattern)
wf = client.workflow 'pipeline'
wf >> Task.simple(:step_a) >> Task.simple(:step_b)
```

### Concurrency Model

**Python SDK:** Uses `multiprocessing.Process` (one OS process per worker) to avoid GIL.

**Ruby SDK:** Uses `Thread` + `concurrent-ruby`'s `ThreadPoolExecutor`. Ruby doesn't have a GIL issue, so threads are sufficient and more lightweight.

## Dependencies

```ruby
# Core HTTP
gem 'faraday', '~> 2.0'
gem 'faraday-net_http_persistent', '~> 2.0'  # Connection pooling
gem 'faraday-retry', '~> 2.0'                # Automatic retries

# Concurrency
gem 'concurrent-ruby', '~> 1.2'             # ThreadPoolExecutor

# JSON
gem 'json', '>= 2.0'
```

## File Structure (Target)

```
lib/
├── conductor.rb                         # Main entry point
├── conductor/
│   ├── version.rb                       # VERSION constant
│   ├── configuration.rb                 # Configuration class
│   ├── configuration/
│   │   └── authentication_settings.rb
│   ├── exceptions.rb                    # All exception classes
│   ├── http/
│   │   ├── rest_client.rb               # Faraday-based HTTP
│   │   ├── api_client.rb                # Auth + serialization
│   │   ├── base_model.rb                # SWAGGER_TYPES pattern
│   │   ├── models/                      # 60+ model classes
│   │   │   ├── task.rb
│   │   │   ├── task_result.rb
│   │   │   ├── workflow.rb
│   │   │   └── ...
│   │   └── api/                         # Resource API classes
│   │       ├── task_resource_api.rb
│   │       ├── workflow_resource_api.rb
│   │       └── ...
│   ├── client/
│   │   ├── orkes_clients.rb             # Main facade
│   │   ├── workflow_client.rb
│   │   ├── task_client.rb
│   │   ├── metadata_client.rb
│   │   └── ...
│   ├── worker/
│   │   ├── worker.rb                    # Worker mixin
│   │   ├── task_context.rb              # Thread-local context
│   │   ├── task_result.rb               # Result constructors
│   │   └── non_retryable_error.rb
│   ├── automator/
│   │   ├── task_runner.rb               # Poll-execute-update
│   │   └── task_handler.rb              # Manages workers
│   └── workflow/
│       ├── conductor_workflow.rb        # Workflow builder
│       ├── workflow_executor.rb
│       └── task/
│           ├── task_interface.rb        # Base with method_missing
│           ├── simple_task.rb
│           ├── fork_task.rb
│           ├── http_task.rb
│           └── ...
```

## Testing Strategy

1. **Unit tests** - Mock HTTP, test logic in isolation
2. **Integration tests** - Against localhost:7001 Conductor server
3. **Example-driven** - All examples must work as integration tests

## Next Steps

1. Implement `RestClient` (Faraday with HTTP/2, connection pooling, retries)
2. Implement `BaseModel` (SWAGGER_TYPES deserialization)
3. Implement `ApiClient` (auth flow, serialization)
4. Generate core models from OpenAPI spec (or hand-code minimal set)
5. Implement first Resource API (TaskResourceApi)
6. Build up domain clients
7. Implement worker framework
8. Implement workflow DSL
9. Add examples and documentation
