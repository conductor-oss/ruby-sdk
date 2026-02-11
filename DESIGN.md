# Conductor Ruby SDK - Design Document

## Overview

This SDK is a Ruby port of the [Conductor Python SDK](https://github.com/conductor-sdk/conductor-python), designed to provide a Ruby-native interface to Conductor OSS while maintaining architectural parity with the Python implementation.

## Design Principles

1. **Follow Python SDK architecture** - Maintain the same layers, patterns, and behaviors
2. **Ruby-idiomatic API** - Use Ruby conventions (snake_case, blocks, symbols) while keeping the same capabilities
3. **Feature parity** - Support all features from the Python SDK
4. **Clean DSL** - Block-based workflow definition with method chaining for output references

## Architecture Layers

```
┌─────────────────────────────────────────────────────────────┐
│                    User Code                                 │
│     Conductor.workflow :name do ... end                     │
│     class MyWorker; include WorkerModule; end               │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────┐
│                  Workflow DSL                                │
│  • Conductor.workflow - Entry point for workflow definition │
│  • WorkflowBuilder - Core DSL engine with task methods      │
│  • WorkflowDefinition - Wrapper with .register/.execute     │
│  • OutputRef/InputRef - Reference expression builders       │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────┐
│                 Worker Framework                             │
│  • WorkerModule - Mixin for class-based workers             │
│  • Worker.define - Block-based worker definition            │
│  • TaskRunner - Polling and execution                       │
│  • TaskHandler - Worker orchestration                       │
│  • Event system - Lifecycle hooks                           │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────┐
│               High-Level Clients (Facades)                   │
│  • WorkflowClient, TaskClient, MetadataClient               │
│  • SchedulerClient, PromptClient, SecretClient              │
│  • IntegrationClient, AuthorizationClient, SchemaClient     │
│  • WorkflowExecutor - Synchronous workflow execution        │
│  • OrkesClients - Factory for all clients                   │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────┐
│              Resource APIs (17 classes)                      │
│  • WorkflowResourceApi, TaskResourceApi                     │
│  • MetadataResourceApi, SchedulerResourceApi                │
│  • EventResourceApi, WorkflowBulkResourceApi                │
│  • PromptResourceApi, SecretResourceApi, etc.               │
│  • Direct mapping to Conductor REST API                     │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────┐
│                HTTP Transport                                │
│  • ApiClient - Auth, serialization, dispatch                │
│  • RestClient - Faraday with HTTP/2, connection pooling     │
│  • BaseModel - SWAGGER_TYPES pattern for serialization      │
│  • 50+ Model classes for request/response types             │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────┐
│                Configuration                                 │
│  • Server URL, auth settings                                │
│  • Token management (class-level cache, TTL refresh)        │
│  • Environment variable support                             │
└─────────────────────────────────────────────────────────────┘
```

## Workflow DSL Design

The SDK provides a clean, Ruby-idiomatic DSL for building workflows:

### Entry Point

```ruby
workflow = Conductor.workflow :order_processing, version: 1, executor: executor do
  # Workflow definition using DSL methods
  user = simple :get_user, user_id: wf[:user_id]
  simple :send_email, email: user[:email]
  output result: user[:name]
end

workflow.register(overwrite: true)
result = workflow.execute(input: { user_id: 123 })
```

### DSL Components

| Component | Purpose |
|-----------|---------|
| `WorkflowBuilder` | Core DSL engine with all task methods |
| `WorkflowDefinition` | Wrapper returned by `Conductor.workflow` |
| `TaskRef` | Stores task metadata, converts to WorkflowTask |
| `OutputRef` | Enables `task[:field]` syntax |
| `InputRef` | Enables `wf[:param]` syntax |
| `ParallelBuilder` | Handles `parallel do...end` blocks |
| `SwitchBuilder` | Handles `decide do...end` blocks |

### Reference Resolution

The DSL automatically converts references to Conductor expression strings:

```ruby
task[:field]              # → "${task_ref.output.field}"
task[:nested][:path]      # → "${task_ref.output.nested.path}"
wf[:param]                # → "${workflow.input.param}"
wf.var(:counter)          # → "${workflow.variables.counter}"
```

### Task Types (25+)

**Basic Tasks:**
- `simple` - Worker task execution
- `http` - HTTP request
- `javascript` - Inline JavaScript execution
- `jq` - JSON JQ transformation
- `set` - Set workflow variables
- `human` - Human/manual task

**Control Flow:**
- `parallel do...end` - Fork/Join execution
- `decide expr do...end` - Switch/case branching
- `when_true/when_false` - Conditional shortcuts
- `loop_over`, `loop_while`, `loop_times` - Iteration
- `sub_workflow` - Call another workflow
- `inline_workflow` - Define sub-workflow inline

**System Tasks:**
- `wait` - Wait for duration or time
- `terminate` - End workflow
- `event` - Publish event
- `wait_for_webhook` - Wait for external callback
- `http_poll` - Poll HTTP endpoint
- `dynamic`, `dynamic_fork` - Runtime task resolution
- `kafka_publish` - Publish to Kafka
- `start_workflow` - Fire-and-forget workflow start

**LLM/AI Tasks:**
- `llm_chat` - Chat completion
- `llm_complete` - Text completion
- `llm_embed` - Generate embeddings
- `llm_index`, `llm_search` - Vector operations
- `llm_store_embeddings`, `llm_search_embeddings` - Vector DB operations
- `generate_image`, `generate_audio` - Media generation
- `list_mcp_tools`, `call_mcp_tool` - MCP integration
- `get_document` - Document retrieval

## Worker Framework Design

See [docs/design/WORKER_DESIGN.md](docs/design/WORKER_DESIGN.md) for detailed design.

### Worker Definition Patterns

```ruby
# Pattern 1: Class-based (recommended for complex workers)
class OrderProcessor
  include Conductor::Worker::WorkerModule
  worker_task 'process_order', poll_interval: 200, thread_count: 5

  def execute(task)
    order_id = get_input(task, 'order_id')
    # Process...
    { processed: true, order_id: order_id }
  end
end

# Pattern 2: Block-based (quick workers)
Conductor::Worker.define('send_email', poll_interval: 100) do |task|
  EmailService.deliver(task.input_data['to'], task.input_data['subject'])
  { sent: true }
end
```

### Concurrency Model

**Python SDK:** Uses `multiprocessing.Process` (one OS process per worker) to avoid GIL.

**Ruby SDK:** Uses `Thread` + `concurrent-ruby`'s `ThreadPoolExecutor`. Ruby's GVL releases during I/O operations, making threads sufficient for typical worker workloads.

## Auth Flow (Matches Python SDK)

| Scenario | Behavior |
|----------|----------|
| No auth configured | Skip auth. No `X-Authorization` header. |
| Initial token fetch | POST `/api/token` → cache token (class-level). |
| `/token` returns 404 | **Disable auth.** Set `auth_configured? = false`. Log "OSS mode". |
| Token TTL expired | Proactively refresh before next request. |
| Server 401/403 with `EXPIRED_TOKEN` | Force-refresh, retry request once. |
| Server 401/403 with `INVALID_TOKEN` | Force-refresh, retry request once. |
| Token refresh fails | Exponential backoff: 2^n seconds, max 5 attempts. |

## File Structure

```
lib/conductor/
├── version.rb                    # VERSION constant
├── configuration.rb              # Configuration class
├── exceptions.rb                 # Exception hierarchy
├── client/                       # High-level client facades (9)
│   ├── workflow_client.rb
│   ├── task_client.rb
│   ├── metadata_client.rb
│   └── ...
├── http/
│   ├── api/                      # Resource API classes (17)
│   │   ├── workflow_resource_api.rb
│   │   ├── task_resource_api.rb
│   │   └── ...
│   ├── models/                   # HTTP models (50+)
│   │   ├── workflow_def.rb
│   │   ├── workflow_task.rb
│   │   └── ...
│   ├── api_client.rb             # Auth + serialization
│   └── rest_client.rb            # Faraday HTTP client
├── orkes/                        # Orkes Cloud specific
│   ├── orkes_clients.rb          # Main factory
│   └── models/
├── worker/                       # Worker framework
│   ├── task_runner.rb            # Polling loop
│   ├── task_handler.rb           # Worker management
│   ├── worker.rb                 # Worker module
│   └── events/                   # Event system
└── workflow/
    ├── dsl/                      # Workflow DSL
    │   ├── workflow_builder.rb   # Core DSL engine
    │   ├── workflow_definition.rb # Wrapper class
    │   ├── task_ref.rb           # Task reference
    │   ├── output_ref.rb         # Output reference
    │   ├── input_ref.rb          # Input reference
    │   ├── parallel_builder.rb   # parallel do...end
    │   └── switch_builder.rb     # decide do...end
    ├── llm/                      # LLM helper classes
    │   ├── chat_message.rb
    │   ├── tool_call.rb
    │   ├── tool_spec.rb
    │   └── embedding_model.rb
    ├── task_type.rb              # Task type constants
    ├── timeout_policy.rb
    └── workflow_executor.rb
```

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

## Testing Strategy

1. **Unit tests** - Mock HTTP, test logic in isolation (~400 tests)
2. **Integration tests** - Against Conductor server (~137 tests)
3. **Example-driven** - All examples in `examples/` directory

```bash
# Run all tests
bundle exec rspec

# Run DSL tests
bundle exec rspec spec/conductor/workflow/dsl/

# Integration tests (requires server)
CONDUCTOR_SERVER_URL=http://localhost:8080/api bundle exec rspec spec/integration/
```

## Related Documents

- [AGENTS.md](AGENTS.md) - Guide for AI coding agents
- [docs/design/WORKER_DESIGN.md](docs/design/WORKER_DESIGN.md) - Worker infrastructure design
- [docs/design/WORKFLOW_DSL.md](docs/design/WORKFLOW_DSL.md) - Workflow DSL design
- [README.md](README.md) - User documentation
- [CONTRIBUTING.md](CONTRIBUTING.md) - Development guidelines
