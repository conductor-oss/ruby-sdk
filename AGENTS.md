# Conductor Ruby SDK - AI Agent Guide

This document provides an overview of the Conductor Ruby SDK codebase for AI coding agents.

## Project Overview

This is the official Ruby SDK for [Conductor OSS](https://github.com/conductor-oss/conductor), a durable workflow orchestration engine. The SDK provides:

- **Workflow DSL** - Ruby-idiomatic block-based workflow definition
- **Worker Framework** - Multi-threaded task execution with events and metrics
- **Full API Coverage** - 17 Resource APIs, 9 high-level clients
- **LLM/AI Tasks** - Chat completion, embeddings, image/audio generation

## Key Design Documents

| Document | Description |
|----------|-------------|
| [DESIGN.md](DESIGN.md) | High-level architecture and design principles |
| [docs/design/WORKER_DESIGN.md](docs/design/WORKER_DESIGN.md) | Worker infrastructure design (polling, events, concurrency) |
| [docs/design/WORKFLOW_DSL.md](docs/design/WORKFLOW_DSL.md) | Workflow DSL design and API reference |
| [README.md](README.md) | User-facing documentation with examples |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Development workflow and guidelines |

---

## Development Requirements

**IMPORTANT: All changes MUST follow these requirements:**

### 1. Linting

After making any changes, always run RuboCop to ensure code style compliance:

```bash
# Check for linting issues
bundle exec rubocop

# Auto-fix safe issues
bundle exec rubocop -a

# Auto-fix all issues (including unsafe)
bundle exec rubocop -A
```

**All code must pass RuboCop checks before being committed.**

### 2. Testing

Tests MUST be run after every change:

```bash
# Run all unit tests (REQUIRED after every change)
bundle exec rspec spec/conductor/

# Run specific test file
bundle exec rspec spec/conductor/workflow/dsl/workflow_builder_spec.rb

# Run with coverage report
bundle exec rspec spec/conductor/ --format documentation
```

### 3. Code Coverage

**Any change MUST increase (or at minimum maintain) code coverage.**

- New features MUST include comprehensive tests
- Bug fixes MUST include regression tests
- Refactoring MUST NOT decrease coverage

Check coverage:
```bash
# Run tests with coverage (if SimpleCov is configured)
COVERAGE=true bundle exec rspec spec/conductor/
```

### 4. Build Verification

Before committing, verify the gem builds correctly:

```bash
# Verify library loads without errors
bundle exec ruby -Ilib -e "require 'conductor'; puts 'OK: ' + Conductor::VERSION"

# Verify syntax of all Ruby files
find lib -name "*.rb" -exec ruby -c {} \;

# Run full test suite
bundle exec rspec
```

### Complete Pre-Commit Checklist

```bash
# 1. Run linter and fix issues
bundle exec rubocop -a

# 2. Run all tests
bundle exec rspec spec/conductor/

# 3. Verify library loads
bundle exec ruby -Ilib -e "require 'conductor'; puts Conductor::VERSION"

# 4. Check for any remaining lint issues
bundle exec rubocop
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    User Code                                 │
│     Conductor.workflow :name do ... end                     │
│     class MyWorker; include WorkerModule; end               │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────┐
│                  Workflow DSL (lib/conductor/workflow/dsl/) │
│  • WorkflowBuilder - Core DSL engine with task methods      │
│  • WorkflowDefinition - Wrapper with .register/.execute     │
│  • TaskRef, OutputRef, InputRef - Reference types           │
│  • ParallelBuilder, SwitchBuilder - Control flow helpers    │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────┐
│                 Worker Framework (lib/conductor/worker/)     │
│  • TaskRunner - Polling and execution                       │
│  • TaskHandler - Worker orchestration                       │
│  • WorkerModule - Mixin for class-based workers             │
│  • Events - Task lifecycle hooks                            │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────┐
│               High-Level Clients (lib/conductor/client/)     │
│  • WorkflowClient, TaskClient, MetadataClient               │
│  • WorkflowExecutor - Synchronous execution                 │
│  • OrkesClients - Factory for all clients                   │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────┐
│              Resource APIs (lib/conductor/http/api/)         │
│  • WorkflowResourceApi, TaskResourceApi, etc.               │
│  • Direct mapping to Conductor REST endpoints               │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────┐
│                HTTP Transport (lib/conductor/http/)          │
│  • ApiClient - Auth, serialization, dispatch                │
│  • RestClient - Faraday-based HTTP client                   │
│  • Models - 50+ request/response models                     │
└─────────────────────────────────────────────────────────────┘
```

---

## Worker Framework (Detailed)

The worker framework provides multi-threaded task execution with a comprehensive event system for interceptors and metrics.

### Component Hierarchy

```
┌─────────────────────────────────────────────────────────────────────┐
│                         User Code                                    │
│  (Worker classes, Worker.define blocks)                             │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       TaskHandler                                    │
│  • Discovers workers (registry + auto-scan)                         │
│  • Resolves configuration (3-tier hierarchy)                        │
│  • Creates one Thread per worker type                               │
│  • Manages lifecycle (start/stop/join)                              │
│  • Aggregates events/metrics                                        │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                    ┌─────────────┼─────────────┐
                    ▼             ▼             ▼
┌─────────────────────┐ ┌─────────────────────┐ ┌─────────────────────┐
│    TaskRunner       │ │    TaskRunner       │ │    TaskRunner       │
│  (Worker A)         │ │  (Worker B)         │ │  (Worker C)         │
│                     │ │                     │ │                     │
│ • ThreadPoolExecutor│ │ • ThreadPoolExecutor│ │ • ThreadPoolExecutor│
│ • Batch polling     │ │ • Batch polling     │ │ • Batch polling     │
│ • Adaptive backoff  │ │ • Adaptive backoff  │ │ • Adaptive backoff  │
│ • Event publishing  │ │ • Event publishing  │ │ • Event publishing  │
└─────────────────────┘ └─────────────────────┘ └─────────────────────┘
```

### Multi-Threading Model

```ruby
# Each TaskRunner has its own ThreadPoolExecutor
class TaskRunner
  def initialize(worker, configuration:, event_dispatcher:)
    @worker = worker
    @executor = Concurrent::ThreadPoolExecutor.new(
      min_threads: 1,
      max_threads: worker.thread_count,  # Configurable per worker
      max_queue: 0,                       # Synchronous handoff
      fallback_policy: :caller_runs
    )
  end
  
  def run
    while @running
      # 1. Check capacity
      available_slots = @worker.thread_count - @running_tasks.size
      
      # 2. Batch poll for tasks
      tasks = batch_poll(available_slots)
      
      # 3. Submit each task to thread pool
      tasks.each do |task|
        future = @executor.post { execute_and_update(task) }
        @running_tasks << future
      end
      
      # 4. Adaptive backoff for empty polls
      apply_backoff if tasks.empty?
    end
  end
end
```

### Event System (Interceptors)

The event system allows hooking into task lifecycle for logging, metrics, and custom behavior:

```ruby
# Event Types
module Conductor::Worker::Events
  PollStarted              # Fired before polling
  PollCompleted            # Fired after successful poll
  PollFailure              # Fired on poll error
  TaskExecutionStarted     # Fired before task execution
  TaskExecutionCompleted   # Fired after successful execution
  TaskExecutionFailure     # Fired on execution error
  TaskUpdateFailure        # CRITICAL: Fired when result update fails
end

# Custom Event Listener (Interceptor)
class MyInterceptor
  def on_poll_started(event)
    puts "Polling for #{event.task_type}..."
  end
  
  def on_task_execution_started(event)
    puts "Starting task #{event.task_id}"
  end
  
  def on_task_execution_completed(event)
    puts "Task #{event.task_id} completed in #{event.duration_ms}ms"
  end
  
  def on_task_execution_failure(event)
    puts "Task #{event.task_id} FAILED: #{event.cause.message}"
    # Send to error tracking service
    ErrorTracker.capture(event.cause, context: { task_id: event.task_id })
  end
end

# Register listener
handler = TaskHandler.new(
  configuration: config,
  event_listeners: [MyInterceptor.new]
)
```

### Event Dispatcher (Thread-Safe)

```ruby
class SyncEventDispatcher
  def initialize
    @listeners = Hash.new { |h, k| h[k] = [] }
    @mutex = Mutex.new
  end
  
  def register(event_type, listener)
    @mutex.synchronize do
      @listeners[event_type] << listener
    end
  end
  
  def publish(event)
    listeners = @mutex.synchronize { @listeners[event.class].dup }
    listeners.each do |listener|
      begin
        listener.call(event)
      rescue StandardError => e
        # Listener failure is isolated - never breaks the worker
        warn "[Conductor] Event listener error: #{e.message}"
      end
    end
  end
end
```

### Metrics Collection

The MetricsCollector listens to events and tracks metrics:

```ruby
class MetricsCollector
  def on_poll_started(event)
    increment("task_poll_total", task_type: event.task_type)
  end
  
  def on_poll_completed(event)
    observe("task_poll_time_seconds", event.duration_ms / 1000.0,
            task_type: event.task_type)
  end
  
  def on_task_execution_completed(event)
    observe("task_execute_time_seconds", event.duration_ms / 1000.0,
            task_type: event.task_type)
    observe("task_result_size_bytes", event.output_size_bytes,
            task_type: event.task_type)
  end
  
  def on_task_execution_failure(event)
    increment("task_execute_error_total",
              task_type: event.task_type,
              exception: event.cause.class.name,
              retryable: event.is_retryable.to_s)
  end
end
```

### Prometheus Metrics

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `task_poll_total` | Counter | `task_type` | Number of poll operations |
| `task_poll_time_seconds` | Histogram | `task_type` | Poll latency |
| `task_poll_error_total` | Counter | `task_type`, `error` | Poll failures |
| `task_execute_time_seconds` | Histogram | `task_type` | Execution time |
| `task_execute_error_total` | Counter | `task_type`, `exception`, `retryable` | Execution failures |
| `task_result_size_bytes` | Histogram | `task_type` | Output size |
| `task_update_failed_total` | Counter | `task_type` | CRITICAL: Update failures |

### Worker Configuration (3-Tier Hierarchy)

Configuration is resolved in order of priority:

1. **Worker-specific environment variable** (highest priority)
   ```bash
   CONDUCTOR_WORKER_PROCESS_ORDER_POLL_INTERVAL=200
   ```

2. **Global worker environment variable**
   ```bash
   CONDUCTOR_WORKER_ALL_POLL_INTERVAL=100
   ```

3. **Code-level default** (lowest priority)
   ```ruby
   worker_task 'process_order', poll_interval: 100
   ```

### Configuration Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `poll_interval` | Integer | 100 | Polling interval in milliseconds |
| `thread_count` | Integer | 1 | Max concurrent tasks per worker |
| `domain` | String | nil | Task domain for isolation |
| `worker_id` | String | auto | Unique worker identifier |
| `poll_timeout` | Integer | 100 | Server-side long poll timeout (ms) |
| `register_task_def` | Boolean | false | Auto-register task definition |
| `paused` | Boolean | false | Pause worker (stop polling) |

### Task Context (Thread-Local)

```ruby
# Access execution context from anywhere in worker code
def execute(task)
  ctx = Conductor::Worker::TaskContext.current
  
  ctx.add_log("Processing task #{ctx.task_id}")
  ctx.add_log("Retry count: #{ctx.retry_count}")
  
  # Long-running task - set callback
  if will_take_long?
    ctx.set_callback_after(60)  # Check back in 60 seconds
    return TaskInProgress.new(output: { status: 'processing' })
  end
  
  { result: 'success' }
end
```

---

## Directory Structure

```
lib/conductor/
├── version.rb                    # VERSION constant
├── configuration.rb              # Configuration class
├── exceptions.rb                 # Exception hierarchy
├── client/                       # High-level client facades
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
│   │   ├── task.rb
│   │   └── ...
│   ├── api_client.rb             # Auth + serialization
│   └── rest_client.rb            # Faraday HTTP client
├── orkes/                        # Orkes Cloud specific
│   ├── orkes_clients.rb          # Main factory
│   └── models/
├── worker/                       # Worker framework
│   ├── task_runner.rb            # Polling loop + ThreadPoolExecutor
│   ├── task_handler.rb           # Worker management
│   ├── worker.rb                 # Worker module
│   ├── worker_config.rb          # Configuration resolver
│   ├── worker_registry.rb        # Global worker registry
│   ├── task_context.rb           # Thread-local context
│   ├── task_in_progress.rb       # Long-running task signal
│   ├── events/                   # Event system
│   │   ├── conductor_event.rb    # Base event class
│   │   ├── task_runner_events.rb # All event types
│   │   ├── sync_event_dispatcher.rb # Thread-safe dispatcher
│   │   ├── listeners.rb          # Listener protocol
│   │   └── listener_registry.rb  # Registration helper
│   └── telemetry/                # Metrics
│       ├── metrics_collector.rb  # Event-based metrics
│       └── prometheus_backend.rb # Prometheus integration
└── workflow/
    ├── dsl/                      # Workflow DSL
    │   ├── workflow_builder.rb   # Core DSL engine (~1000 lines)
    │   ├── workflow_definition.rb # Wrapper class
    │   ├── task_ref.rb           # Task reference
    │   ├── output_ref.rb         # Output reference (task[:field])
    │   ├── input_ref.rb          # Input reference (wf[:param])
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

---

## Key Files to Understand

### Workflow DSL (Most Important)

1. **`lib/conductor/workflow/dsl/workflow_builder.rb`** (~1000 lines)
   - Core DSL engine with all task methods
   - `simple`, `http`, `wait`, `terminate`, `sub_workflow`
   - `parallel`, `decide`, `loop_over`, `when_true/when_false`
   - LLM tasks: `llm_chat`, `llm_embed`, `generate_image`, etc.
   - Value resolution: `OutputRef`, `InputRef` → expression strings

2. **`lib/conductor/workflow/dsl/workflow_definition.rb`**
   - Wrapper class returned by `Conductor.workflow`
   - Provides `.register()`, `.execute()`, `.call()` methods
   - Delegates to WorkflowExecutor for execution

3. **`lib/conductor/workflow/dsl/task_ref.rb`**
   - Stores task metadata during DSL evaluation
   - Converts to `WorkflowTask` model for serialization
   - Supports `[]` operator for output references

### Worker Framework

1. **`lib/conductor/worker/task_runner.rb`**
   - Main polling loop with adaptive backoff
   - ThreadPoolExecutor for concurrent task execution
   - Event publishing for lifecycle hooks

2. **`lib/conductor/worker/worker.rb`**
   - `WorkerModule` mixin for class-based workers
   - `worker_task` class method for registration
   - `Conductor::Worker.define` for block-based workers

3. **`lib/conductor/worker/events/`**
   - Event classes for task lifecycle
   - SyncEventDispatcher for thread-safe event publishing
   - ListenerRegistry for listener management

### HTTP Layer

1. **`lib/conductor/http/api_client.rb`**
   - Token management with TTL-based refresh
   - Request serialization, response deserialization
   - Retry logic for 401/403 errors

2. **`lib/conductor/http/models/workflow_def.rb`**
   - WorkflowDef model with all workflow properties
   - Used for registration and serialization

---

## Common Patterns

### Creating a Workflow

```ruby
workflow = Conductor.workflow :my_workflow, version: 1, executor: executor do
  user = simple :get_user, user_id: wf[:user_id]
  simple :send_email, email: user[:email]
  output result: user[:name]
end

workflow.register(overwrite: true)
result = workflow.execute(input: { user_id: 123 })
```

### Task Reference Flow

```
DSL Method Call           TaskRef Created           WorkflowTask Generated
─────────────────────────────────────────────────────────────────────────
simple :foo, x: wf[:y]  → TaskRef(ref: 'foo_ref')  → WorkflowTask(
                           task_name: 'foo'           name: 'foo'
                           inputs: {...}              type: 'SIMPLE'
                                                      input_parameters: {...}
                                                    )
```

### Output References

```ruby
task[:field]              # → OutputRef → "${task_ref.output.field}"
task[:nested][:path]      # → OutputRef → "${task_ref.output.nested.path}"
wf[:param]                # → InputRef  → "${workflow.input.param}"
wf.var(:counter)          # → InputRef  → "${workflow.variables.counter}"
```

---

## Testing

### Test Structure

```
spec/
├── conductor/
│   ├── workflow/
│   │   ├── dsl/
│   │   │   └── workflow_builder_spec.rb  # 52 DSL tests
│   │   └── llm_tasks_spec.rb             # LLM helper tests
│   ├── client/
│   ├── http/
│   └── worker/
└── integration/                           # Requires live server
```

### Running Tests

```bash
# Run all unit tests (REQUIRED after every change)
bundle exec rspec spec/conductor/

# Run DSL tests specifically
bundle exec rspec spec/conductor/workflow/dsl/

# Run worker tests
bundle exec rspec spec/conductor/worker/

# Run with documentation format
bundle exec rspec --format documentation

# Integration tests (requires Conductor server)
CONDUCTOR_SERVER_URL=http://localhost:8080/api bundle exec rspec spec/integration/
```

---

## Making Changes

### Adding a New Task Type

1. Add constant to `lib/conductor/workflow/task_type.rb`
2. Add DSL method to `lib/conductor/workflow/dsl/workflow_builder.rb`
3. Handle conversion in `lib/conductor/workflow/dsl/task_ref.rb`
4. Add tests in `spec/conductor/workflow/dsl/workflow_builder_spec.rb`
5. Update examples in `examples/workflow_dsl.rb`
6. Run linter: `bundle exec rubocop -a`
7. Run tests: `bundle exec rspec spec/conductor/`

### Adding a New API Endpoint

1. Add method to appropriate Resource API in `lib/conductor/http/api/`
2. Add corresponding method to high-level client in `lib/conductor/client/`
3. Add tests in `spec/conductor/http/api/` and `spec/conductor/client/`
4. Run linter: `bundle exec rubocop -a`
5. Run tests: `bundle exec rspec spec/conductor/`

### Modifying Worker Behavior

1. Review `docs/design/WORKER_DESIGN.md` for detailed design
2. Modify `lib/conductor/worker/task_runner.rb` for polling behavior
3. Modify `lib/conductor/worker/worker.rb` for worker definition
4. Add tests in `spec/conductor/worker/`
5. Run linter: `bundle exec rubocop -a`
6. Run tests: `bundle exec rspec spec/conductor/`

### Adding Event Listeners / Interceptors

1. Create class implementing listener methods (`on_poll_started`, `on_task_execution_completed`, etc.)
2. Register with TaskHandler via `event_listeners:` option
3. Add tests in `spec/conductor/worker/events/`

---

## Important Conventions

- **Snake case** for methods and variables
- **Keyword arguments** for optional parameters
- **Blocks** for control flow (`parallel do`, `decide do`)
- **Symbol-to-string** task names are auto-converted
- **Output references** use `[]` operator (`task[:field]`)
- **Input references** use `wf[:param]` syntax
- **Thread safety** - Use Mutex for shared state in event system

---

## Dependencies

**Runtime:**
- `faraday ~> 2.0` - HTTP client
- `faraday-net_http_persistent ~> 2.0` - Connection pooling
- `faraday-retry ~> 2.0` - Automatic retries
- `concurrent-ruby ~> 1.2` - Thread pool executor

**Development:**
- `rspec ~> 3.0` - Testing
- `webmock ~> 3.0` - HTTP mocking
- `rubocop ~> 1.0` - Linting
