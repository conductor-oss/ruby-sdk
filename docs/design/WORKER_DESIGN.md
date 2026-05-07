# Conductor Ruby SDK - Worker Infrastructure Design

## Table of Contents

1. [Overview & Goals](#overview--goals)
2. [Architecture Overview](#architecture-overview)
3. [Ruby vs Python Concurrency](#ruby-vs-python-concurrency)
4. [Core Components](#core-components)
5. [Three Runner Models](#three-runner-models)
6. [Worker Definition Patterns](#worker-definition-patterns)
7. [Task Context System](#task-context-system)
8. [Behavioral Algorithms](#behavioral-algorithms)
9. [Event System](#event-system)
10. [Configuration System](#configuration-system)
11. [Task Definition Auto-Registration](#task-definition-auto-registration)
12. [File Structure](#file-structure)
13. [Implementation Phases](#implementation-phases)

---

## Overview & Goals

### Purpose

This document specifies the design for the Conductor Ruby SDK's worker infrastructure - the system that polls for tasks from a Conductor server, executes them using user-defined workers, and reports results back.

### Goals

1. **Full parity with Python SDK** - Support all features from the Python worker SDK including batch polling, adaptive backoff, capacity management, events, and metrics
2. **Ruby-idiomatic API** - Use Ruby conventions (blocks, mixins, snake_case) while maintaining the same capabilities
3. **Production-grade** - Handle edge cases, failures, and high-throughput scenarios reliably
4. **Extensible** - Support custom event listeners, metrics backends, and execution models
5. **Multiple concurrency models** - Support threads (default), Ractors (opt-in), and fibers (opt-in)

### Non-Goals

- Workflow definition DSL (covered in separate design)
- HTTP client implementation (already exists)
- Model serialization (already exists)

---

## Architecture Overview

### Component Hierarchy

```
┌─────────────────────────────────────────────────────────────────────┐
│                         User Code                                    │
│  (Worker classes, @worker_task methods, Worker.define blocks)       │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       TaskHandler                                    │
│  • Discovers workers (registry + auto-scan)                         │
│  • Resolves configuration (3-tier hierarchy)                        │
│  • Creates one Thread/Ractor per worker                             │
│  • Manages lifecycle (start/stop/join)                              │
│  • Aggregates events/metrics                                        │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                    ┌─────────────┼─────────────┐
                    ▼             ▼             ▼
┌─────────────────────┐ ┌─────────────────────┐ ┌─────────────────────┐
│    TaskRunner       │ │    TaskRunner       │ │ RactorTaskRunner    │
│  (Thread-based)     │ │  (Thread-based)     │ │ (Ractor-based)      │
│                     │ │                     │ │                     │
│ • ThreadPoolExecutor│ │ • FiberExecutor     │ │ • Ractor isolation  │
│ • Batch polling     │ │   (async gem)       │ │ • Own HTTP client   │
│ • Capacity mgmt     │ │ • Batch polling     │ │ • Message passing   │
│ • Event publishing  │ │ • Capacity mgmt     │ │ • Event publishing  │
└─────────────────────┘ └─────────────────────┘ └─────────────────────┘
          │                       │                       │
          ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       TaskResourceApi                                │
│  • poll_task / batch_poll                                           │
│  • update_task                                                      │
│  • HTTP communication via ApiClient                                 │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       Conductor Server                               │
└─────────────────────────────────────────────────────────────────────┘
```

### Comparison to Python SDK

| Aspect | Python SDK | Ruby SDK |
|--------|-----------|----------|
| **Worker isolation** | One OS process per worker (`multiprocessing.Process`) | One Thread per worker (default), Ractor opt-in |
| **Task concurrency** | `ThreadPoolExecutor` (sync) or `asyncio` (async) | `Concurrent::ThreadPoolExecutor` (default), Fiber opt-in |
| **Why different** | Python GIL blocks ALL threads during CPU work | Ruby GVL releases during I/O (HTTP, sleep) |
| **Async model** | `asyncio` event loop, `async/await` | `async` gem with Fibers (opt-in) |
| **Event dispatch** | `SyncEventDispatcher` with `threading.Lock` | `SyncEventDispatcher` with `Mutex` |
| **Config resolution** | 3-tier: worker env → global env → code | Same |
| **HTTP client** | `requests` (sync), `httpx` (async) | `Faraday` with `net_http_persistent` |

---

## Ruby vs Python Concurrency

### Why Threads Work for Ruby Workers

Python uses processes because the GIL (Global Interpreter Lock) prevents true thread parallelism for **any** Python code. Ruby's GVL (Global VM Lock) is similar but crucially different:

**Ruby GVL releases during:**
- Network I/O (HTTP requests, socket operations)
- File I/O
- `sleep` calls
- C extension calls that release the GVL

**Worker operations are I/O-bound:**
1. Poll HTTP endpoint (GVL released)
2. Execute worker (may be CPU-bound, but typically I/O)
3. Update HTTP endpoint (GVL released)

This means Ruby threads provide **real concurrency** for typical worker workloads, making process-per-worker unnecessary overhead for most use cases.

### When to Use Ractors

Ractors provide true parallelism (no GVL sharing) but with restrictions:
- No shared mutable state between Ractors
- Limited gem compatibility (many gems use global state)
- Requires Ruby 3.1+

**Use Ractors when:**
- Worker performs CPU-intensive computation
- Worker doesn't need shared state
- All dependencies are Ractor-safe

### When to Use Fibers

Fibers provide lightweight cooperative concurrency within a single thread:
- ~400 bytes per fiber vs ~8KB per thread
- Can handle thousands of concurrent I/O operations
- Requires non-blocking I/O throughout

**Use Fibers when:**
- Extremely high concurrency (hundreds of concurrent tasks)
- All operations are non-blocking (no blocking gem calls)
- Memory is constrained

---

## Core Components

### 1. TaskHandler

The top-level orchestrator that manages all workers.

```ruby
module Conductor
  module Worker
    class TaskHandler
      # Initialize with optional workers and configuration
      # @param workers [Array<WorkerInterface>] Pre-created worker instances
      # @param configuration [Configuration] Conductor configuration
      # @param scan_for_annotated_workers [Boolean] Auto-discover @worker_task methods
      # @param import_modules [Array<String>] Ruby files/modules to require (triggers registration)
      # @param event_listeners [Array<TaskRunnerEventsListener>] Custom event listeners
      # @param metrics_settings [MetricsSettings] Metrics configuration
      def initialize(
        workers: nil,
        configuration: nil,
        scan_for_annotated_workers: true,
        import_modules: nil,
        event_listeners: nil,
        metrics_settings: nil
      )
      end

      # Start all worker threads/ractors
      # @return [self]
      def start
      end

      # Stop all workers gracefully
      # @param timeout [Integer] Seconds to wait before force-killing (default: 5)
      # @return [self]
      def stop(timeout: 5)
      end

      # Wait for all workers to complete (blocking)
      # @return [self]
      def join
      end

      # Check if handler is running
      # @return [Boolean]
      def running?
      end

      # Get list of registered workers
      # @return [Array<Worker>]
      def workers
      end
    end
  end
end
```

**Responsibilities:**
1. Discover workers from registry + auto-scan
2. Resolve configuration for each worker (3-tier hierarchy)
3. Create appropriate runner (TaskRunner or RactorTaskRunner) based on config
4. Create one Thread (or Ractor) per worker
5. Manage lifecycle (start/stop/join)
6. Create shared EventDispatcher and register listeners
7. Optionally start MetricsProvider

**Context Manager Pattern:**
```ruby
Conductor::Worker::TaskHandler.new(configuration: config) do |handler|
  handler.start
  handler.join
end
# Automatically calls stop on block exit
```

### 2. TaskRunner (Thread-based)

The polling loop that runs in a dedicated Thread.

```ruby
module Conductor
  module Worker
    class TaskRunner
      # Initialize runner for a specific worker
      # @param worker [Worker] The worker to run
      # @param configuration [Configuration] Conductor configuration
      # @param event_dispatcher [SyncEventDispatcher] Shared event dispatcher
      # @param executor [Symbol] :thread_pool (default) or :fiber
      def initialize(worker, configuration:, event_dispatcher:, executor: :thread_pool)
      end

      # Main polling loop (runs until stopped)
      def run
      end

      # Single iteration of the polling loop
      def run_once
      end

      # Signal the runner to stop
      def shutdown
      end

      # Check if runner is running
      # @return [Boolean]
      def running?
      end
    end
  end
end
```

**Internal State:**
```ruby
@worker              # Worker instance
@configuration       # Conductor configuration
@task_client         # TaskClient for HTTP operations
@event_dispatcher    # SyncEventDispatcher for publishing events
@executor            # Concurrent::ThreadPoolExecutor or FiberExecutor
@running_tasks       # Set of running futures/fibers
@consecutive_empty_polls  # Counter for adaptive backoff
@auth_failures       # Counter for auth failure backoff
@shutdown            # AtomicBoolean for graceful shutdown
@last_poll_time      # Time of last poll (for backoff calculation)
```

### 3. RactorTaskRunner

The Ractor-based runner for CPU-bound workers requiring true parallelism.

```ruby
module Conductor
  module Worker
    class RactorTaskRunner
      # Initialize runner for a specific worker (runs inside Ractor)
      # @param worker [Worker] The worker to run (must be Ractor-safe)
      # @param configuration [Configuration] Conductor configuration (serializable parts only)
      def initialize(worker, configuration:)
      end

      # Main polling loop (creates HTTP client inside Ractor)
      def run
      end

      # Called by TaskHandler to receive events from Ractor
      # @return [Array<ConductorEvent>] Events from this poll cycle
      def drain_events
      end
    end
  end
end
```

**Key Differences from TaskRunner:**
1. Creates `TaskClient` **inside** `run()` (Ractors can't share objects)
2. Uses Ractor-local storage for TaskContext (not `Thread.current`)
3. Events are collected and sent to main Ractor via `Ractor.yield` for aggregation
4. No ThreadPoolExecutor - sequential execution within the Ractor (parallelism comes from multiple Ractors)

### 4. Worker

The user-facing worker definition that wraps an execute function.

```ruby
module Conductor
  module Worker
    class Worker
      attr_reader :task_definition_name, :execute_function, :config
      attr_accessor :domain, :poll_interval, :thread_count, :worker_id,
                    :register_task_def, :overwrite_task_def, :strict_schema,
                    :paused, :poll_timeout, :isolation, :executor

      # Initialize a worker
      # @param task_definition_name [String] Task type name in Conductor
      # @param execute_function [Proc, Method] Function to execute tasks
      # @param options [Hash] Worker configuration options
      def initialize(task_definition_name, execute_function = nil, **options, &block)
      end

      # Execute a task
      # @param task [Task] The task to execute
      # @return [TaskResult, TaskInProgress, Hash] Execution result
      def execute(task)
      end

      # Get polling interval in seconds
      # @return [Float]
      def polling_interval_seconds
      end

      # Check if worker is async (for auto-detection, not used in Ruby)
      # @return [Boolean]
      def async?
      end
    end
  end
end
```

**Execute Function Return Type Handling:**

| Return Type | Behavior |
|-------------|----------|
| `TaskResult` | Use directly (set task_id, workflow_instance_id) |
| `TaskInProgress` | Create `IN_PROGRESS` result with `callback_after_seconds` |
| `Hash` | Wrap in `COMPLETED` TaskResult as output_data |
| `true` | `COMPLETED` with empty output |
| `false` | `FAILED` with empty output |
| `nil` | `COMPLETED` with empty output |
| Any other object | `COMPLETED` with `{ result: object }` output |
| Raises `NonRetryableError` | `FAILED_WITH_TERMINAL_ERROR` |
| Raises any `StandardError` | `FAILED` with error message |

### 5. WorkerConfig

Configuration resolver with 3-tier hierarchy.

```ruby
module Conductor
  module Worker
    class WorkerConfig
      # Resolve configuration for a worker
      # @param worker_name [String] Task definition name
      # @param defaults [Hash] Code-level defaults from worker definition
      # @return [Hash] Resolved configuration
      def self.resolve(worker_name, defaults = {})
      end

      # Configuration properties with types and defaults
      PROPERTIES = {
        poll_interval: { type: :integer, default: 100 },      # milliseconds
        thread_count: { type: :integer, default: 1 },
        domain: { type: :string, default: nil },
        worker_id: { type: :string, default: -> { generate_worker_id } },
        poll_timeout: { type: :integer, default: 100 },       # milliseconds
        register_task_def: { type: :boolean, default: false },
        overwrite_task_def: { type: :boolean, default: true },
        strict_schema: { type: :boolean, default: false },
        paused: { type: :boolean, default: false },
        isolation: { type: :symbol, default: :thread },       # :thread or :ractor
        executor: { type: :symbol, default: :thread_pool }    # :thread_pool or :fiber
      }.freeze
    end
  end
end
```

**Resolution Priority (highest to lowest):**

1. **Worker-specific environment variable:**
   - `conductor.worker.{task_name}.{property}` (dotted)
   - `CONDUCTOR_WORKER_{TASK_NAME}_{PROPERTY}` (uppercase)

2. **Global worker environment variable:**
   - `conductor.worker.all.{property}` (dotted)
   - `CONDUCTOR_WORKER_ALL_{PROPERTY}` (uppercase)

3. **Legacy environment variable:**
   - `CONDUCTOR_WORKER_{PROPERTY}` (old format)

4. **Code-level default:**
   - Value passed to `worker_task` or `Worker.new`

**Boolean Parsing:** Accepts `true/1/yes` and `false/0/no` (case-insensitive).

---

## Three Runner Models

### Model 1: TaskRunner with ThreadPoolExecutor (Default)

```
┌─────────────────────────────────────────────────────────────┐
│                    Worker Thread                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              TaskRunner.run()                        │    │
│  │  ┌────────────────────────────────────────────────┐ │    │
│  │  │           Polling Loop                          │ │    │
│  │  │  1. Check capacity                              │ │    │
│  │  │  2. Adaptive backoff                            │ │    │
│  │  │  3. Batch poll                                  │ │    │
│  │  │  4. Submit tasks to executor ─────────────────┐ │ │    │
│  │  │  5. Loop                                      │ │ │    │
│  │  └───────────────────────────────────────────────┘ │ │    │
│  └──────────────────────────────────────────────────│─┘    │
│                                                      │      │
│  ┌──────────────────────────────────────────────────▼─┐    │
│  │        Concurrent::ThreadPoolExecutor               │    │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐  │    │
│  │  │ Thread 1│ │ Thread 2│ │ Thread 3│ │ Thread N│  │    │
│  │  │ Task A  │ │ Task B  │ │ Task C  │ │  idle   │  │    │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘  │    │
│  │  (thread_count = N)                                │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

**Configuration:**
```ruby
worker_task 'my_task', thread_count: 5, poll_interval: 100
# or
Worker.new('my_task', thread_count: 5, executor: :thread_pool)
```

**Characteristics:**
- One dedicated thread for the polling loop
- ThreadPoolExecutor with `thread_count` threads for task execution
- GVL released during HTTP I/O, so threads provide real concurrency
- Best for: Most workloads (I/O-bound or mixed)

### Model 2: TaskRunner with FiberExecutor (Opt-in)

```
┌─────────────────────────────────────────────────────────────┐
│                    Worker Thread                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              TaskRunner.run()                        │    │
│  │  ┌────────────────────────────────────────────────┐ │    │
│  │  │      Async Event Loop (via async gem)          │ │    │
│  │  │  ┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐      │ │    │
│  │  │  │Fiber 1│ │Fiber 2│ │Fiber 3│ │Fiber N│      │ │    │
│  │  │  │Task A │ │Task B │ │Task C │ │ poll  │      │ │    │
│  │  │  └───────┘ └───────┘ └───────┘ └───────┘      │ │    │
│  │  │  (cooperative scheduling, single thread)       │ │    │
│  │  │  (thread_count = concurrency limit via Semaphore) │   │
│  │  └────────────────────────────────────────────────┘ │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

**Configuration:**
```ruby
worker_task 'my_task', thread_count: 100, executor: :fiber
# Requires: gem 'async' in Gemfile
```

**Characteristics:**
- Single thread with fiber-based cooperative concurrency
- Requires `async` gem (optional dependency, loaded lazily)
- `thread_count` becomes fiber concurrency limit (semaphore)
- All I/O must be non-blocking (async gem provides non-blocking HTTP)
- Best for: Very high concurrency I/O-bound tasks (hundreds/thousands)

**Lazy Loading:**
```ruby
# In fiber_executor.rb
def self.load_async_gem
  require 'async'
  require 'async/http'
rescue LoadError
  raise Conductor::ConfigurationError,
    "The 'async' gem is required for fiber executor. Add `gem 'async'` to your Gemfile."
end
```

### Model 3: RactorTaskRunner (Opt-in)

```
┌────────────────────────────────────────────────────────────────────────┐
│                         Main Thread (TaskHandler)                       │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                    Event Aggregation Loop                         │  │
│  │  • Receives events from Ractors via Ractor.receive               │  │
│  │  • Dispatches to shared EventDispatcher                          │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│           ▲                    ▲                    ▲                   │
│           │ events             │ events             │ events            │
└───────────┼────────────────────┼────────────────────┼────────────────────┘
            │                    │                    │
┌───────────┴──────┐  ┌─────────┴────────┐  ┌───────┴──────────┐
│    Ractor 1      │  │    Ractor 2      │  │    Ractor 3      │
│ ┌──────────────┐ │  │ ┌──────────────┐ │  │ ┌──────────────┐ │
│ │RactorTaskRunner│ │  │ │RactorTaskRunner│ │  │ │RactorTaskRunner│ │
│ │  Worker A    │ │  │ │  Worker B    │ │  │ │  Worker C    │ │
│ │              │ │  │ │              │ │  │ │              │ │
│ │ Own HTTP     │ │  │ │ Own HTTP     │ │  │ │ Own HTTP     │ │
│ │ client       │ │  │ │ client       │ │  │ │ client       │ │
│ │              │ │  │ │              │ │  │ │              │ │
│ │ Sequential   │ │  │ │ Sequential   │ │  │ │ Sequential   │ │
│ │ task exec    │ │  │ │ task exec    │ │  │ │ task exec    │ │
│ └──────────────┘ │  │ └──────────────┘ │  │ └──────────────┘ │
│ (no GVL sharing) │  │ (no GVL sharing) │  │ (no GVL sharing) │
└──────────────────┘  └──────────────────┘  └──────────────────┘
      True parallel execution across Ractors
```

**Configuration:**
```ruby
worker_task 'cpu_intensive_task', isolation: :ractor, thread_count: 4
# Creates 4 Ractors, each running the same worker
```

**Characteristics:**
- True parallelism (each Ractor has its own GVL)
- HTTP client created inside Ractor (can't be shared)
- Events sent to main thread via Ractor messaging
- `thread_count` = number of Ractors (each processes one task at a time)
- Worker must be Ractor-safe (no shared mutable state)
- Requires Ruby 3.1+
- Best for: CPU-intensive workers

**Ractor Constraints:**
```ruby
# These will NOT work in Ractor-based workers:
- Global variables (@@, $)
- Class instance variables
- Mutating shared objects
- Many gems that use global state

# These WILL work:
- Pure functions
- Immutable data
- Ractor-local state via Ractor.current[:key]
```

---

## Worker Definition Patterns

### Pattern 1: Class-based with Module Mixin

```ruby
class OrderProcessor
  include Conductor::Worker::WorkerMixin

  worker_task 'process_order',
    poll_interval: 200,
    thread_count: 5,
    domain: 'orders'

  def execute(task)
    order_id = task.input_data['order_id']
    amount = task.input_data['amount']

    # Process the order...
    result = process(order_id, amount)

    # Return hash (auto-wrapped in COMPLETED TaskResult)
    { processed: true, order_id: order_id, total: result.total }
  end
end

# Usage
handler = TaskHandler.new(workers: [OrderProcessor.new])
```

### Pattern 2: Block-based with `Worker.define`

```ruby
Conductor::Worker.define('send_notification', poll_interval: 100, thread_count: 3) do |task|
  recipient = task.input_data['recipient']
  message = task.input_data['message']

  NotificationService.send(to: recipient, body: message)

  { sent: true, recipient: recipient }
end

# Workers registered automatically, discovered by TaskHandler
handler = TaskHandler.new(scan_for_annotated_workers: true)
```

### Pattern 3: Method Annotation with `worker_task`

```ruby
module MyWorkers
  extend Conductor::Worker::Annotatable

  worker_task 'greet_user', poll_interval: 50
  def self.greet(name:, greeting: 'Hello')
    "#{greeting}, #{name}!"
  end

  worker_task 'calculate_total', thread_count: 10
  def self.calculate(items:)
    total = items.sum { |item| item['price'] * item['quantity'] }
    { total: total, item_count: items.size }
  end
end

# Usage
handler = TaskHandler.new(
  scan_for_annotated_workers: true,
  import_modules: ['./lib/my_workers']
)
```

### Pattern 4: Keyword Argument Mapping

When the execute function has keyword arguments, they are automatically mapped from `task.input_data`:

```ruby
# Worker definition with keyword args
worker_task 'process_payment'
def process_payment(order_id:, amount:, currency: 'USD')
  # order_id, amount extracted from task.input_data
  # currency uses default if not in input_data
  PaymentGateway.charge(order_id, amount, currency)
end

# Task input_data: { "order_id" => "123", "amount" => 99.99 }
# Mapped to: process_payment(order_id: "123", amount: 99.99, currency: 'USD')
```

### Pattern 5: Full Task Access

```ruby
worker_task 'audit_task'
def audit(task)
  # Full access to task object
  puts "Task ID: #{task.task_id}"
  puts "Workflow: #{task.workflow_instance_id}"
  puts "Retry count: #{task.retry_count}"
  puts "Poll count: #{task.poll_count}"

  # Access input
  data = task.input_data

  # Return result
  { audited: true }
end
```

---

## Task Context System

TaskContext provides execution context accessible from anywhere in the worker code.

### Thread-local Storage (TaskRunner)

```ruby
module Conductor
  module Worker
    class TaskContext
      # Get current context (thread-local)
      # @return [TaskContext, nil]
      def self.current
        Thread.current[:conductor_task_context]
      end

      # Set current context (internal use)
      def self.current=(context)
        Thread.current[:conductor_task_context] = context
      end

      # Clear current context (internal use)
      def self.clear
        Thread.current[:conductor_task_context] = nil
      end

      attr_reader :task, :task_result

      def initialize(task, task_result)
        @task = task
        @task_result = task_result
      end

      # Convenience accessors
      def task_id
        @task.task_id
      end

      def workflow_instance_id
        @task.workflow_instance_id
      end

      def retry_count
        @task.retry_count || 0
      end

      def poll_count
        @task.poll_count || 0
      end

      def input
        @task.input_data || {}
      end

      def task_def_name
        @task.task_def_name
      end

      # Mutable context methods
      def add_log(message)
        @task_result.log(message)
      end

      def set_callback_after(seconds)
        @task_result.callback_after_seconds = seconds
      end

      def set_output(output_data)
        @task_result.output_data = output_data
      end

      def callback_after_seconds
        @task_result.callback_after_seconds
      end
    end
  end
end
```

### Fiber Storage (FiberExecutor)

```ruby
# When using fiber executor, context stored in Fiber.current.storage
def self.current
  if defined?(Fiber.current.storage)
    Fiber.current.storage[:conductor_task_context]
  else
    Thread.current[:conductor_task_context]
  end
end
```

### Ractor Storage (RactorTaskRunner)

```ruby
# Ractors use Ractor.current for isolation
def self.current
  Ractor.current[:conductor_task_context]
rescue
  Thread.current[:conductor_task_context]
end
```

### Usage in Worker Code

```ruby
worker_task 'my_task'
def execute(task)
  ctx = Conductor::Worker::TaskContext.current

  # Log progress
  ctx.add_log("Starting processing for #{ctx.task_id}")

  # Check retry count to avoid infinite loops
  if ctx.retry_count > 3
    raise NonRetryableError, "Too many retries"
  end

  # Long-running task - set callback
  if will_take_long?
    ctx.set_callback_after(60)  # Check back in 60 seconds
    return TaskInProgress.new(output: { status: 'processing' })
  end

  # Process...
  result = do_work(ctx.input)

  ctx.add_log("Completed processing")
  result
end
```

---

## Behavioral Algorithms

### Algorithm 1: Main Polling Loop (`run_once`)

```ruby
def run_once
  # 1. Cleanup completed tasks (removes done futures from tracking set)
  cleanup_completed_tasks

  # 2. Check capacity
  current_capacity = @running_tasks.size
  if current_capacity >= @max_workers
    sleep(0.001)  # 1ms sleep to prevent busy-waiting
    return
  end

  available_slots = @max_workers - current_capacity

  # 3. Adaptive backoff for empty polls
  if @consecutive_empty_polls > 0
    backoff_ms = [1 * (2 ** [@consecutive_empty_polls, 10].min), @poll_interval].min
    elapsed_ms = (Time.now - @last_poll_time) * 1000
    if elapsed_ms < backoff_ms
      sleep((backoff_ms - elapsed_ms) / 1000.0)
      return
    end
  end

  # 4. Batch poll for tasks
  @last_poll_time = Time.now
  tasks = batch_poll(available_slots)

  # 5. Submit tasks for execution
  if tasks.empty?
    @consecutive_empty_polls += 1
  else
    @consecutive_empty_polls = 0
    tasks.each do |task|
      future = @executor.post { execute_and_update(task) }
      @running_tasks << future
    end
  end
end
```

### Algorithm 2: Batch Poll with Auth Backoff

```ruby
def batch_poll(count)
  # Skip if worker is paused
  return [] if @worker.paused

  # Auth failure exponential backoff (capped at 60 seconds)
  if @auth_failures > 0
    backoff_seconds = [2 ** @auth_failures, 60].min
    elapsed = Time.now - @last_auth_failure_time
    if elapsed < backoff_seconds
      return []
    end
  end

  # Publish PollStarted event
  @event_dispatcher.publish(Events::PollStarted.new(
    task_type: @worker.task_definition_name,
    worker_id: @worker_id,
    poll_count: @poll_count
  ))

  start_time = Time.now

  begin
    # HTTP batch poll
    tasks = @task_client.batch_poll(
      @worker.task_definition_name,
      count: count,
      timeout: @worker.poll_timeout,
      worker_id: @worker_id,
      domain: @worker.domain.presence  # nil if empty string
    )

    duration_ms = (Time.now - start_time) * 1000
    @poll_count += 1

    # Publish PollCompleted event
    @event_dispatcher.publish(Events::PollCompleted.new(
      task_type: @worker.task_definition_name,
      duration_ms: duration_ms,
      tasks_received: tasks.size
    ))

    # Reset auth failures on success
    @auth_failures = 0

    tasks
  rescue AuthorizationError => e
    @auth_failures += 1
    @last_auth_failure_time = Time.now
    duration_ms = (Time.now - start_time) * 1000

    @event_dispatcher.publish(Events::PollFailure.new(
      task_type: @worker.task_definition_name,
      duration_ms: duration_ms,
      cause: e
    ))

    @logger.warn("Auth failure ##{@auth_failures}, backing off #{[2 ** @auth_failures, 60].min}s")
    []
  rescue StandardError => e
    duration_ms = (Time.now - start_time) * 1000

    @event_dispatcher.publish(Events::PollFailure.new(
      task_type: @worker.task_definition_name,
      duration_ms: duration_ms,
      cause: e
    ))

    @logger.error("Poll failed: #{e.message}")
    []
  end
end
```

### Algorithm 3: Task Execution

```ruby
def execute_and_update(task)
  task_result = execute_task(task)

  # Skip update for TaskInProgress (task stays in IN_PROGRESS state)
  return if task_result.nil? || task_result.is_a?(TaskInProgress)

  update_task_with_retry(task_result)
end

def execute_task(task)
  # Create initial TaskResult for context
  initial_result = TaskResult.new
  initial_result.task_id = task.task_id
  initial_result.workflow_instance_id = task.workflow_instance_id
  initial_result.worker_id = @worker_id

  # Set task context (thread-local)
  TaskContext.current = TaskContext.new(task, initial_result)

  start_time = Time.now

  # Publish TaskExecutionStarted
  @event_dispatcher.publish(Events::TaskExecutionStarted.new(
    task_type: @worker.task_definition_name,
    task_id: task.task_id,
    worker_id: @worker_id,
    workflow_instance_id: task.workflow_instance_id
  ))

  begin
    # Execute worker
    output = @worker.execute(task)

    duration_ms = (Time.now - start_time) * 1000

    # Handle different return types
    task_result = case output
    when TaskResult
      output
    when TaskInProgress
      result = TaskResult.in_progress
      result.callback_after_seconds = output.callback_after_seconds
      result.output_data = output.output
      result
    when Hash
      result = TaskResult.complete
      result.output_data = output
      result
    when true
      TaskResult.complete
    when false
      TaskResult.failed('Worker returned false')
    when nil
      TaskResult.complete
    else
      result = TaskResult.complete
      result.output_data = { 'result' => output }
      result
    end

    # Set IDs and merge context modifications
    task_result.task_id = task.task_id
    task_result.workflow_instance_id = task.workflow_instance_id
    task_result.worker_id = @worker_id

    # Merge logs and callback_after from context
    ctx = TaskContext.current
    task_result.logs ||= []
    task_result.logs.concat(ctx.task_result.logs || [])
    task_result.callback_after_seconds ||= ctx.callback_after_seconds

    output_size = task_result.output_data.to_json.bytesize rescue 0

    # Publish TaskExecutionCompleted
    @event_dispatcher.publish(Events::TaskExecutionCompleted.new(
      task_type: @worker.task_definition_name,
      task_id: task.task_id,
      worker_id: @worker_id,
      workflow_instance_id: task.workflow_instance_id,
      duration_ms: duration_ms,
      output_size_bytes: output_size
    ))

    task_result

  rescue NonRetryableError => e
    duration_ms = (Time.now - start_time) * 1000
    task_result = TaskResult.failed_with_terminal_error(e.message)
    task_result.task_id = task.task_id
    task_result.workflow_instance_id = task.workflow_instance_id
    task_result.log("NonRetryableError: #{e.class}: #{e.message}")

    @event_dispatcher.publish(Events::TaskExecutionFailure.new(
      task_type: @worker.task_definition_name,
      task_id: task.task_id,
      worker_id: @worker_id,
      workflow_instance_id: task.workflow_instance_id,
      duration_ms: duration_ms,
      cause: e,
      is_retryable: false
    ))

    task_result

  rescue StandardError => e
    duration_ms = (Time.now - start_time) * 1000
    task_result = TaskResult.failed(e.message)
    task_result.task_id = task.task_id
    task_result.workflow_instance_id = task.workflow_instance_id
    task_result.log("Error: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")

    @event_dispatcher.publish(Events::TaskExecutionFailure.new(
      task_type: @worker.task_definition_name,
      task_id: task.task_id,
      worker_id: @worker_id,
      workflow_instance_id: task.workflow_instance_id,
      duration_ms: duration_ms,
      cause: e,
      is_retryable: true
    ))

    task_result

  ensure
    TaskContext.clear
  end
end
```

### Algorithm 4: Task Update with Retry

```ruby
RETRY_BACKOFFS = [0, 10, 20, 30].freeze  # seconds

def update_task_with_retry(task_result)
  RETRY_BACKOFFS.each_with_index do |backoff, attempt|
    sleep(backoff) if backoff > 0

    begin
      @task_client.update_task(task_result)
      return  # Success
    rescue StandardError => e
      @logger.error("Task update failed (attempt #{attempt + 1}/#{RETRY_BACKOFFS.size}): #{e.message}")

      if attempt == RETRY_BACKOFFS.size - 1
        # All retries exhausted - CRITICAL: task result is lost
        @logger.fatal("CRITICAL: Task update failed after #{RETRY_BACKOFFS.size} attempts. " \
                      "Task #{task_result.task_id} result is LOST.")

        @event_dispatcher.publish(Events::TaskUpdateFailure.new(
          task_type: @worker.task_definition_name,
          task_id: task_result.task_id,
          worker_id: @worker_id,
          workflow_instance_id: task_result.workflow_instance_id,
          cause: e,
          retry_count: RETRY_BACKOFFS.size,
          task_result: task_result  # Include result for recovery
        ))
      end
    end
  end
end
```

### Algorithm 5: Capacity Management

The semaphore/capacity is held during BOTH execute AND update to prevent over-polling:

```ruby
# In ThreadPoolExecutor model:
def execute_and_update(task)
  # This entire method runs in a thread pool thread
  # The "slot" is occupied from the moment the task is submitted
  # until this method returns (after execute + update)

  task_result = execute_task(task)
  return if task_result.nil? || task_result.is_a?(TaskInProgress)

  # Still occupying the slot during update retries
  update_task_with_retry(task_result)

  # Slot released when this method returns and future completes
end

# In FiberExecutor model:
def execute_and_update_fiber(task)
  @semaphore.acquire  # Acquire slot

  begin
    task_result = execute_task(task)
    return if task_result.nil? || task_result.is_a?(TaskInProgress)

    update_task_with_retry(task_result)
  ensure
    @semaphore.release  # Release slot only after update
  end
end
```

---

## Event System

### Event Hierarchy

```ruby
module Conductor
  module Worker
    module Events
      # Base event with timestamp
      class ConductorEvent
        attr_reader :timestamp

        def initialize
          @timestamp = Time.now.utc
        end
      end

      # Base for task runner events
      class TaskRunnerEvent < ConductorEvent
        attr_reader :task_type

        def initialize(task_type:)
          super()
          @task_type = task_type
        end
      end

      # Poll started
      class PollStarted < TaskRunnerEvent
        attr_reader :worker_id, :poll_count

        def initialize(task_type:, worker_id:, poll_count:)
          super(task_type: task_type)
          @worker_id = worker_id
          @poll_count = poll_count
        end
      end

      # Poll completed successfully
      class PollCompleted < TaskRunnerEvent
        attr_reader :duration_ms, :tasks_received

        def initialize(task_type:, duration_ms:, tasks_received:)
          super(task_type: task_type)
          @duration_ms = duration_ms
          @tasks_received = tasks_received
        end
      end

      # Poll failed
      class PollFailure < TaskRunnerEvent
        attr_reader :duration_ms, :cause

        def initialize(task_type:, duration_ms:, cause:)
          super(task_type: task_type)
          @duration_ms = duration_ms
          @cause = cause
        end
      end

      # Task execution started
      class TaskExecutionStarted < TaskRunnerEvent
        attr_reader :task_id, :worker_id, :workflow_instance_id

        def initialize(task_type:, task_id:, worker_id:, workflow_instance_id:)
          super(task_type: task_type)
          @task_id = task_id
          @worker_id = worker_id
          @workflow_instance_id = workflow_instance_id
        end
      end

      # Task execution completed
      class TaskExecutionCompleted < TaskRunnerEvent
        attr_reader :task_id, :worker_id, :workflow_instance_id,
                    :duration_ms, :output_size_bytes

        def initialize(task_type:, task_id:, worker_id:, workflow_instance_id:,
                       duration_ms:, output_size_bytes:)
          super(task_type: task_type)
          @task_id = task_id
          @worker_id = worker_id
          @workflow_instance_id = workflow_instance_id
          @duration_ms = duration_ms
          @output_size_bytes = output_size_bytes
        end
      end

      # Task execution failed
      class TaskExecutionFailure < TaskRunnerEvent
        attr_reader :task_id, :worker_id, :workflow_instance_id,
                    :duration_ms, :cause, :is_retryable

        def initialize(task_type:, task_id:, worker_id:, workflow_instance_id:,
                       duration_ms:, cause:, is_retryable: true)
          super(task_type: task_type)
          @task_id = task_id
          @worker_id = worker_id
          @workflow_instance_id = workflow_instance_id
          @duration_ms = duration_ms
          @cause = cause
          @is_retryable = is_retryable
        end
      end

      # Task update failed (CRITICAL - result lost)
      class TaskUpdateFailure < TaskRunnerEvent
        attr_reader :task_id, :worker_id, :workflow_instance_id,
                    :cause, :retry_count, :task_result

        def initialize(task_type:, task_id:, worker_id:, workflow_instance_id:,
                       cause:, retry_count:, task_result:)
          super(task_type: task_type)
          @task_id = task_id
          @worker_id = worker_id
          @workflow_instance_id = workflow_instance_id
          @cause = cause
          @retry_count = retry_count
          @task_result = task_result  # For recovery
        end
      end
    end
  end
end
```

### SyncEventDispatcher

```ruby
module Conductor
  module Worker
    class SyncEventDispatcher
      def initialize
        @listeners = Hash.new { |h, k| h[k] = [] }
        @mutex = Mutex.new
      end

      # Register a listener for an event type
      # @param event_type [Class] Event class to listen for
      # @param listener [Proc, #call] Callable to invoke
      def register(event_type, listener)
        @mutex.synchronize do
          @listeners[event_type] << listener unless @listeners[event_type].include?(listener)
        end
      end

      # Unregister a listener
      def unregister(event_type, listener)
        @mutex.synchronize do
          @listeners[event_type].delete(listener)
        end
      end

      # Publish an event to all registered listeners
      # @param event [ConductorEvent] Event to publish
      def publish(event)
        listeners = @mutex.synchronize { @listeners[event.class].dup }

        listeners.each do |listener|
          begin
            listener.call(event)
          rescue StandardError => e
            # Listener failure is isolated - never breaks the worker
            warn "Event listener error for #{event.class}: #{e.message}"
          end
        end
      end

      # Check if there are listeners for an event type
      def has_listeners?(event_type)
        @mutex.synchronize { @listeners[event_type].any? }
      end

      # Clear all listeners (for testing)
      def clear
        @mutex.synchronize { @listeners.clear }
      end
    end
  end
end
```

### Listener Protocol (Duck Typing)

```ruby
module Conductor
  module Worker
    # Listener protocol - implement any/all of these methods
    # Methods are optional - only implemented methods are called
    module TaskRunnerEventsListener
      # @param event [PollStarted]
      def on_poll_started(event); end

      # @param event [PollCompleted]
      def on_poll_completed(event); end

      # @param event [PollFailure]
      def on_poll_failure(event); end

      # @param event [TaskExecutionStarted]
      def on_task_execution_started(event); end

      # @param event [TaskExecutionCompleted]
      def on_task_execution_completed(event); end

      # @param event [TaskExecutionFailure]
      def on_task_execution_failure(event); end

      # @param event [TaskUpdateFailure]
      def on_task_update_failure(event); end
    end
  end
end
```

### Listener Registration Helper

```ruby
module Conductor
  module Worker
    class ListenerRegistry
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

      EVENT_METHOD_MAP = {
        Events::PollStarted => :on_poll_started,
        Events::PollCompleted => :on_poll_completed,
        Events::PollFailure => :on_poll_failure,
        Events::TaskExecutionStarted => :on_task_execution_started,
        Events::TaskExecutionCompleted => :on_task_execution_completed,
        Events::TaskExecutionFailure => :on_task_execution_failure,
        Events::TaskUpdateFailure => :on_task_update_failure
      }.freeze
    end
  end
end
```

### MetricsCollector

The SDK supports legacy and canonical metric surfaces, selected by the
`WORKER_CANONICAL_METRICS` environment variable. `MetricsCollector.create`
returns the appropriate collector (`LegacyMetricsCollector` or
`CanonicalMetricsCollector`):

```ruby
metrics = Conductor::Worker::Telemetry::MetricsCollector.create(backend: :prometheus)
```

See [docs/METRICS_AND_INTERCEPTORS.md](../METRICS_AND_INTERCEPTORS.md) for the
full legacy and canonical metrics catalogs, label reference, and migration
guide.

---

## Configuration System

### Environment Variable Formats

For a worker named `process_order` and property `poll_interval`:

**Worker-specific (highest priority):**
```bash
# Dotted format (preferred)
conductor.worker.process_order.poll_interval=200

# Uppercase format
CONDUCTOR_WORKER_PROCESS_ORDER_POLL_INTERVAL=200
```

**Global (applies to all workers):**
```bash
# Dotted format
conductor.worker.all.poll_interval=100

# Uppercase format
CONDUCTOR_WORKER_ALL_POLL_INTERVAL=100
```

**Legacy (lowest priority):**
```bash
CONDUCTOR_WORKER_POLL_INTERVAL=100
```

### Configuration Properties

| Property | Type | Default | Env Var Suffix | Description |
|----------|------|---------|----------------|-------------|
| `poll_interval` | Integer | 100 | `POLL_INTERVAL` | Polling interval in milliseconds |
| `thread_count` | Integer | 1 | `THREAD_COUNT` | Max concurrent tasks (or Ractor count) |
| `domain` | String | nil | `DOMAIN` | Task domain for isolation |
| `worker_id` | String | auto | `WORKER_ID` | Unique worker identifier |
| `poll_timeout` | Integer | 100 | `POLL_TIMEOUT` | Server-side long poll timeout (ms) |
| `register_task_def` | Boolean | false | `REGISTER_TASK_DEF` | Auto-register task definition |
| `overwrite_task_def` | Boolean | true | `OVERWRITE_TASK_DEF` | Overwrite existing task defs |
| `strict_schema` | Boolean | false | `STRICT_SCHEMA` | Enforce strict JSON schema |
| `paused` | Boolean | false | `PAUSED` | Pause worker (stop polling) |
| `isolation` | Symbol | :thread | `ISOLATION` | `:thread` or `:ractor` |
| `executor` | Symbol | :thread_pool | `EXECUTOR` | `:thread_pool` or `:fiber` |

### Auto-generated Worker ID

```ruby
def self.generate_worker_id
  hostname = Socket.gethostname rescue 'unknown'
  pid = Process.pid
  thread_id = Thread.current.object_id.to_s(16)
  "#{hostname}-#{pid}-#{thread_id}"
end
```

---

## Task Definition Auto-Registration

When `register_task_def: true`, the worker automatically registers its task definition on startup.

### Registration Flow

```ruby
def register_task_definition
  return unless @worker.register_task_def

  # Build TaskDef from worker config or template
  task_def = @worker.task_def_template&.dup || TaskDef.new
  task_def.name = @worker.task_definition_name

  # Generate JSON schemas if possible
  if @worker.execute_function.respond_to?(:parameters)
    input_schema = generate_input_schema(@worker.execute_function)
    output_schema = generate_output_schema(@worker.execute_function)

    register_schemas(input_schema, output_schema) if input_schema || output_schema
  end

  # Register or update task definition
  if @worker.overwrite_task_def
    begin
      @metadata_client.update_task_def(task_def)
    rescue ApiError => e
      if e.status == 404
        @metadata_client.register_task_def([task_def])
      else
        raise
      end
    end
  else
    # Check if exists first
    begin
      @metadata_client.get_task_def(@worker.task_definition_name)
      @logger.info("Task definition '#{@worker.task_definition_name}' already exists, skipping registration")
    rescue ApiError => e
      if e.status == 404
        @metadata_client.register_task_def([task_def])
      else
        raise
      end
    end
  end

  @logger.info("Registered task definition: #{@worker.task_definition_name}")
rescue StandardError => e
  # Graceful degradation - worker still starts
  @logger.warn("Failed to register task definition: #{e.message}")
end
```

### JSON Schema Generation

```ruby
def generate_input_schema(func)
  return nil unless func.respond_to?(:parameters)

  properties = {}
  required = []

  func.parameters.each do |type, name|
    next if name == :task  # Skip if taking full task object

    properties[name.to_s] = { 'type' => 'string' }  # Default type

    case type
    when :keyreq  # Required keyword arg
      required << name.to_s
    when :key     # Optional keyword arg
      # Not required
    end
  end

  return nil if properties.empty?

  schema = {
    '$schema' => 'http://json-schema.org/draft-07/schema#',
    'type' => 'object',
    'properties' => properties
  }
  schema['required'] = required unless required.empty?
  schema['additionalProperties'] = !@worker.strict_schema

  schema
end
```

---

## File Structure

```
lib/conductor/
├── worker/
│   ├── worker.rb                    # Worker class
│   ├── worker_mixin.rb              # WorkerMixin module for class-based workers
│   ├── worker_config.rb             # Configuration resolver
│   ├── worker_registry.rb           # Global worker registry
│   ├── task_handler.rb              # Top-level orchestrator
│   ├── task_runner.rb               # Thread-based runner
│   ├── ractor_task_runner.rb        # Ractor-based runner (Phase 2)
│   ├── fiber_executor.rb            # Fiber executor (Phase 3)
│   ├── task_context.rb              # Execution context
│   ├── task_in_progress.rb          # TaskInProgress return type
│   └── exceptions.rb                # Worker-specific exceptions
├── worker/events/
│   ├── conductor_event.rb           # Base event class
│   ├── task_runner_events.rb        # All 7 event classes
│   ├── sync_event_dispatcher.rb     # Thread-safe event dispatcher
│   ├── listener_registry.rb         # Listener registration helper
│   └── listeners.rb                 # Listener protocol module
├── worker/telemetry/
│   ├── metrics_collector.rb         # Factory (WORKER_CANONICAL_METRICS gate)
│   ├── legacy_metrics_collector.rb  # Legacy metric set
│   ├── canonical_metrics_collector.rb # Canonical metric set
│   ├── prometheus_backend.rb        # Legacy Prometheus backend
│   ├── canonical_prometheus_backend.rb # Canonical Prometheus backend
│   └── null_backend.rb              # No-op backend
└── exceptions.rb                    # Add NonRetryableError
```

---

## Implementation Phases

### Phase 1: Core Thread-based Runner (MVP)

**Goal:** Production-ready thread-based workers with all Python SDK behavioral parity.

**Components:**
1. `Worker` class with execute function handling
2. `WorkerMixin` module for class-based workers
3. `worker_task` DSL method and global registry
4. `WorkerConfig` with 3-tier resolution
5. `TaskRunner` with ThreadPoolExecutor
6. `TaskHandler` orchestrator
7. `TaskContext` (thread-local)
8. `TaskInProgress` return type
9. All 7 event classes
10. `SyncEventDispatcher`
11. `ListenerRegistry`
12. `MetricsCollector` with null backend

**Algorithms:**
- Batch polling with dynamic sizing
- Adaptive backoff for empty polls
- Auth failure exponential backoff
- Task update with 4 retries
- Capacity management (semaphore during execute + update)

**Tests:**
- Unit tests for each component
- Integration tests against local Conductor server
- All Python SDK test scenarios ported

### Phase 2: Ractor-based Runner

**Goal:** True parallelism for CPU-bound workers.

**Components:**
1. `RactorTaskRunner` 
2. Ractor-local TaskContext storage
3. Event aggregation via Ractor messaging
4. `isolation: :ractor` configuration

**Constraints:**
- Requires Ruby 3.1+
- Worker must be Ractor-safe
- HTTP client created inside Ractor

### Phase 3: Fiber Executor

**Goal:** High-concurrency I/O-bound workers.

**Components:**
1. `FiberExecutor` using `async` gem
2. Fiber-local TaskContext storage
3. `executor: :fiber` configuration
4. Async-compatible HTTP client

**Constraints:**
- Requires `async` gem (optional dependency)
- All I/O must be non-blocking
- Worker must not use blocking operations

### Phase 4: Metrics & Observability

**Goal:** Production observability.

**Components:**
1. `PrometheusBackend` with full metric set
2. HTTP metrics endpoint
3. Health check endpoint
4. Datadog backend (optional)

### Phase 5: Advanced Features

**Goal:** Feature parity with all Python SDK capabilities.

**Components:**
1. Task definition auto-registration with JSON schemas
2. Worker auto-discovery (directory scanning)
3. Graceful shutdown with drain
4. Dynamic worker pause/resume

---

## Appendix A: Complete Example

```ruby
require 'conductor'

# Configure
config = Conductor::Configuration.new(
  server_api_url: 'http://localhost:8080/api'
)

# Define workers

# Class-based worker
class OrderProcessor
  include Conductor::Worker::WorkerMixin

  worker_task 'process_order',
    poll_interval: 200,
    thread_count: 5

  def execute(task)
    order = task.input_data
    ctx = Conductor::Worker::TaskContext.current

    ctx.add_log("Processing order #{order['id']}")

    # Simulate processing
    result = process_order(order)

    ctx.add_log("Order processed successfully")

    { status: 'completed', total: result.total }
  end

  private

  def process_order(order)
    # Business logic here
    OpenStruct.new(total: order['amount'] * 1.1)
  end
end

# Block-based worker
Conductor::Worker.define('send_notification', thread_count: 3) do |task|
  recipient = task.input_data['recipient']
  message = task.input_data['message']

  # Send notification
  NotificationService.send(to: recipient, body: message)

  { sent: true }
end

# Method-based worker with keyword args
module PaymentWorkers
  extend Conductor::Worker::Annotatable

  worker_task 'charge_card', poll_interval: 100
  def self.charge_card(card_token:, amount:, currency: 'USD')
    result = PaymentGateway.charge(card_token, amount, currency)
    { transaction_id: result.id, status: result.status }
  end
end

# Custom event listener
class AuditLogger
  def on_task_execution_completed(event)
    puts "[AUDIT] Task #{event.task_id} completed in #{event.duration_ms}ms"
  end

  def on_task_execution_failure(event)
    puts "[AUDIT] Task #{event.task_id} FAILED: #{event.cause.message}"
  end
end

# Start workers
Conductor::Worker::TaskHandler.new(
  configuration: config,
  workers: [OrderProcessor.new],
  scan_for_annotated_workers: true,
  event_listeners: [AuditLogger.new]
) do |handler|
  puts "Starting workers..."
  handler.start

  # Handle shutdown gracefully
  trap('INT') { handler.stop }
  trap('TERM') { handler.stop }

  handler.join
  puts "Workers stopped."
end
```

---

## Appendix B: Migration from Current Implementation

The current `lib/conductor/worker/` has basic implementations that need to be replaced:

| Current | New |
|---------|-----|
| `worker.rb` (WorkerModule) | `worker.rb` + `worker_mixin.rb` |
| `task_runner.rb` (simple) | `task_runner.rb` (full algorithms) |
| N/A | `task_handler.rb` |
| N/A | `worker_config.rb` |
| N/A | `task_context.rb` |
| N/A | `events/*` |
| N/A | `telemetry/*` |

**Migration Strategy:**
1. Keep existing files during development
2. Build new implementation alongside
3. Update `lib/conductor.rb` to use new implementation
4. Remove old files after testing

---

*Last Updated: February 2026*
*Status: Design Complete - Ready for Implementation*
