# Conductor Ruby SDK - Workflow DSL Design

## Table of Contents

1. [Overview](#overview)
2. [Design Goals](#design-goals)
3. [Architecture](#architecture)
4. [Core Components](#core-components)
5. [DSL Syntax Reference](#dsl-syntax-reference)
6. [Reference Types](#reference-types)
7. [Control Flow](#control-flow)
8. [Task Types](#task-types)
9. [Implementation Details](#implementation-details)
10. [Examples](#examples)

---

## Overview

The Conductor Ruby SDK provides a clean, Ruby-idiomatic DSL for defining workflows. The DSL uses blocks, method chaining, and Ruby's dynamic features to create a natural syntax for workflow definition.

### Basic Example

```ruby
workflow = Conductor.workflow :order_processing, version: 1, executor: executor do
  # Access workflow inputs with wf[:param]
  user = simple :get_user, user_id: wf[:user_id]
  
  # Reference task outputs with task[:field]
  order = simple :create_order, user_email: user[:email]
  
  # Parallel execution
  parallel do
    simple :ship_order, order_id: order[:id]
    simple :send_confirmation, email: user[:email]
  end
  
  # Set workflow output
  output order_id: order[:id], status: 'completed'
end

# Register and execute
workflow.register(overwrite: true)
result = workflow.execute(input: { user_id: 123 }, wait_for_seconds: 60)
```

---

## Design Goals

1. **Ruby-idiomatic** - Use Ruby conventions (blocks, symbols, keyword arguments)
2. **Type-safe references** - `OutputRef` and `InputRef` for compile-time safety
3. **Minimal boilerplate** - Auto-generate reference names, convert types automatically
4. **Composable** - Nested blocks for control flow (`parallel`, `decide`, `loop_over`)
5. **Full feature coverage** - Support all Conductor task types including LLM tasks

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    User Code                                 │
│     Conductor.workflow :name do ... end                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ instance_eval(&block)
┌─────────────────────────────────────────────────────────────┐
│                  WorkflowBuilder                             │
│  • Holds workflow metadata (name, version, description)     │
│  • Contains task method implementations                     │
│  • Collects TaskRefs during DSL evaluation                  │
│  • Resolves OutputRef/InputRef to expression strings        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ returns WorkflowDefinition
┌─────────────────────────────────────────────────────────────┐
│                WorkflowDefinition                            │
│  • Wraps WorkflowBuilder                                    │
│  • Provides .register(), .execute(), .call() methods        │
│  • Delegates to WorkflowExecutor for execution              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ to_workflow_def
┌─────────────────────────────────────────────────────────────┐
│              Conductor::Http::Models::WorkflowDef           │
│  • Serializable workflow definition                         │
│  • Contains WorkflowTask array                              │
│  • Ready for API submission                                 │
└─────────────────────────────────────────────────────────────┘
```

---

## Core Components

### 1. WorkflowBuilder (`lib/conductor/workflow/dsl/workflow_builder.rb`)

The core DSL engine containing:

- **Workflow metadata methods**: `description`, `timeout`, `owner_email`, `restartable`, `failure_workflow`, `output`
- **Task methods**: `simple`, `http`, `wait`, `terminate`, `sub_workflow`, etc.
- **Control flow methods**: `parallel`, `decide`, `when_true`, `when_false`, `loop_over`, `loop_while`
- **LLM methods**: `llm_chat`, `llm_embed`, `generate_image`, etc.
- **Value resolution**: `resolve_value`, `resolve_hash` for OutputRef/InputRef conversion

**Key responsibility**: During `instance_eval`, task methods create `TaskRef` objects and return them, allowing chaining like `user[:email]`.

### 2. WorkflowDefinition (`lib/conductor/workflow/dsl/workflow_definition.rb`)

Wrapper class returned by `Conductor.workflow`:

```ruby
class WorkflowDefinition
  def initialize(builder, executor: nil)
    @builder = builder
    @executor = executor
  end

  def register(overwrite: false)
    # Register workflow via executor
  end

  def execute(input: {}, wait_for_seconds: nil, ...)
    # Execute workflow via executor
  end

  def call(...)
    execute(...)
  end

  def to_workflow_def
    @builder.to_workflow_def
  end
end
```

### 3. TaskRef (`lib/conductor/workflow/dsl/task_ref.rb`)

Stores task metadata during DSL evaluation:

```ruby
class TaskRef
  attr_reader :ref_name, :task_name, :task_type, :input_parameters, :options

  def [](field)
    OutputRef.new(ref_name, field.to_s)
  end

  def to_workflow_task
    # Convert to Conductor::Http::Models::WorkflowTask
  end
end
```

### 4. OutputRef (`lib/conductor/workflow/dsl/output_ref.rb`)

Enables `task[:field]` syntax:

```ruby
class OutputRef
  def initialize(task_ref, path)
    @task_ref = task_ref
    @path = path
  end

  def [](field)
    OutputRef.new(@task_ref, "#{@path}.#{field}")
  end

  def to_s
    "${#{@task_ref}.output.#{@path}}"
  end
end
```

### 5. InputRef (`lib/conductor/workflow/dsl/input_ref.rb`)

Enables `wf[:param]` syntax:

```ruby
class InputRef
  def [](field)
    InputFieldRef.new("workflow.input.#{field}")
  end

  def var(name)
    InputFieldRef.new("workflow.variables.#{name}")
  end
end

class InputFieldRef
  def [](field)
    InputFieldRef.new("#{@path}.#{field}")
  end

  def to_s
    "${#{@path}}"
  end
end
```

### 6. Control Flow Builders

**ParallelBuilder** - Collects branches for `parallel do...end`:

```ruby
class ParallelBuilder
  def initialize(parent_builder)
    @parent = parent_builder
    @branches = [[]]
  end

  def method_missing(name, *args, **kwargs, &block)
    # Delegate to parent builder, collect tasks into current branch
  end

  def finalize
    @branches  # Array of task arrays
  end
end
```

**SwitchBuilder** - Handles `decide expr do...end`:

```ruby
class SwitchBuilder
  def on(value, &block)
    # Add case branch
  end

  def otherwise(&block)
    # Add default branch
  end
end
```

---

## DSL Syntax Reference

### Workflow Definition

```ruby
Conductor.workflow :name, version: 1, executor: executor do
  description 'Workflow description'
  timeout 3600                        # Timeout in seconds
  owner_email 'owner@example.com'
  restartable true
  failure_workflow 'failure_handler'
  
  # ... tasks ...
  
  output key: value                   # Workflow output parameters
end
```

### Input/Output References

```ruby
# Workflow inputs
wf[:user_id]                          # "${workflow.input.user_id}"
wf[:data][:items]                     # "${workflow.input.data.items}"
wf.var(:counter)                      # "${workflow.variables.counter}"

# Task outputs
task[:result]                         # "${task_ref.output.result}"
task[:data][:nested][:field]          # "${task_ref.output.data.nested.field}"
```

---

## Control Flow

### Parallel Execution

```ruby
parallel do
  simple :task_a
  simple :task_b
  simple :task_c
end
```

Generates FORK_JOIN → tasks → JOIN structure.

### Conditional Branching

```ruby
decide user[:tier] do
  on 'gold' do
    simple :apply_gold_discount
  end
  on 'silver' do
    simple :apply_silver_discount
  end
  otherwise do
    simple :no_discount
  end
end
```

### Conditional Shortcuts

```ruby
when_true order[:is_premium] do
  simple :apply_discount
end

when_false order[:validated] do
  terminate :failed, 'Validation failed'
end
```

### Loops

```ruby
# Loop N times
loop_times 3 do
  simple :process_batch
end

# Loop with condition
loop_while '$.has_more == true' do
  simple :fetch_page
end

# Loop over items
loop_over users[:list] do
  simple :process_user, user: iteration[:item]
end
```

---

## Task Types

### Basic Tasks

| Method | Type | Description |
|--------|------|-------------|
| `simple :name, **inputs` | SIMPLE | Worker task execution |
| `http :name, url:, method:, body:, headers:` | HTTP | HTTP request |
| `javascript :name, script:, **bindings` | INLINE | Inline JavaScript |
| `jq :name, query:, **inputs` | JSON_JQ_TRANSFORM | JQ transformation |
| `set var: value` | SET_VARIABLE | Set workflow variables |
| `human :name, assignee:, display_name:` | HUMAN | Human/manual task |

### Wait and Events

| Method | Type | Description |
|--------|------|-------------|
| `wait seconds` | WAIT | Wait for duration |
| `wait until_time: 'ISO8601'` | WAIT | Wait until time |
| `event :name, sink:, **payload` | EVENT | Publish event |
| `wait_for_webhook :name, matches: {}` | WAIT_FOR_WEBHOOK | Wait for callback |

### Workflow Control

| Method | Type | Description |
|--------|------|-------------|
| `terminate :status, 'reason'` | TERMINATE | End workflow |
| `sub_workflow :name, workflow:, version:` | SUB_WORKFLOW | Call workflow |
| `start_workflow :name, workflow:, **inputs` | START_WORKFLOW | Fire-and-forget |
| `inline_workflow :name do...end` | SUB_WORKFLOW | Inline sub-workflow |

### Dynamic Tasks

| Method | Type | Description |
|--------|------|-------------|
| `dynamic :name, dynamic_task_param:` | DYNAMIC | Runtime task name |
| `dynamic_fork :name, tasks_param:, tasks_input_param:` | FORK_JOIN_DYNAMIC | Dynamic parallel |
| `http_poll :name, url:, termination_condition:` | HTTP_POLL | Poll until condition |

### LLM/AI Tasks

| Method | Type | Description |
|--------|------|-------------|
| `llm_chat :name, provider:, model:, messages:` | LLM_CHAT_COMPLETE | Chat completion |
| `llm_complete :name, provider:, model:, prompt:` | LLM_TEXT_COMPLETE | Text completion |
| `llm_embed :name, provider:, model:, text:` | LLM_GENERATE_EMBEDDINGS | Generate embeddings |
| `llm_store_embeddings :name, vector_db:, index:, embeddings:` | LLM_STORE_EMBEDDINGS | Store in vector DB |
| `llm_search_embeddings :name, vector_db:, index:, embeddings:` | LLM_SEARCH_EMBEDDINGS | Search vector DB |
| `generate_image :name, provider:, model:, prompt:` | GENERATE_IMAGE | Image generation |
| `generate_audio :name, provider:, model:, text:, voice:` | GENERATE_AUDIO | Text-to-speech |
| `list_mcp_tools :name, mcp_server:` | LIST_MCP_TOOLS | List MCP tools |
| `call_mcp_tool :name, mcp_server:, method:, arguments:` | CALL_MCP_TOOL | Call MCP tool |
| `get_document :name, url:, media_type:` | GET_DOCUMENT | Retrieve document |

---

## Implementation Details

### Reference Resolution

The DSL automatically converts references to Conductor expression strings:

```ruby
def resolve_value(value)
  case value
  when OutputRef, InputRef
    value.to_s                    # "${task_ref.output.field}"
  when Hash
    resolve_hash(value)           # Recursively resolve
  when Array
    value.map { |v| resolve_value(v) }
  else
    value                         # Literals pass through
  end
end
```

### Task Reference Name Generation

```ruby
def generate_ref_name(task_name)
  base = "#{task_name}_ref"
  @ref_counter[base] += 1
  @ref_counter[base] == 1 ? base : "#{base}_#{@ref_counter[base]}"
end
```

This ensures unique reference names:
- First `simple :get_user` → `get_user_ref`
- Second `simple :get_user` → `get_user_ref_2`

### Workflow Task Conversion

`TaskRef#to_workflow_task` converts DSL representation to `WorkflowTask` model:

```ruby
def to_workflow_task
  wf_task = Conductor::Http::Models::WorkflowTask.new(
    name: @task_name,
    task_reference_name: @ref_name,
    type: @task_type,
    input_parameters: @input_parameters
  )
  
  # Handle special task types (FORK_JOIN, SWITCH, DO_WHILE, etc.)
  case @task_type
  when TaskType::FORK_JOIN
    wf_task.fork_tasks = convert_branches(@options[:fork_branches])
  when TaskType::SWITCH
    wf_task.expression = @options[:expression]
    wf_task.decision_cases = @options[:decision_cases]
    wf_task.default_case = @options[:default_case]
  # ... etc
  end
  
  wf_task
end
```

---

## Examples

### E-commerce Order Processing

```ruby
workflow = Conductor.workflow :order_processing, version: 1, executor: executor do
  description 'Process customer orders'
  timeout 3600
  
  # Validate order
  validation = simple :validate_order,
    order_id: wf[:order_id],
    customer_id: wf[:customer_id]
  
  # Check inventory
  inventory = simple :check_inventory,
    items: validation[:items]
  
  # Conditional based on stock
  decide inventory[:in_stock] do
    on 'true' do
      # Process payment
      payment = simple :process_payment,
        amount: validation[:total],
        customer_id: wf[:customer_id]
      
      # Parallel fulfillment
      parallel do
        simple :ship_order, order_id: wf[:order_id]
        simple :send_confirmation, email: validation[:customer_email]
        simple :update_analytics, order_data: validation[:result]
      end
    end
    
    otherwise do
      simple :notify_backorder, items: inventory[:missing_items]
      terminate :failed, 'Items out of stock'
    end
  end
  
  output order_id: wf[:order_id], status: 'completed'
end
```

### AI Document Processing

```ruby
workflow = Conductor.workflow :document_analysis, version: 1, executor: executor do
  # Fetch document
  doc = get_document :fetch_doc,
    url: wf[:document_url],
    media_type: wf[:media_type]
  
  # Generate embeddings
  embeddings = llm_embed :embed_doc,
    provider: 'openai',
    model: 'text-embedding-3-small',
    text: doc[:content]
  
  # Store in vector database
  llm_store_embeddings :store_vectors,
    vector_db: 'pinecone',
    index: 'documents',
    embeddings: embeddings[:embeddings],
    id: wf[:doc_id],
    metadata: { source: wf[:document_url] }
  
  # Analyze with LLM
  analysis = llm_chat :analyze,
    provider: 'openai',
    model: 'gpt-4',
    messages: [
      { role: :system, message: 'Analyze the following document and extract key insights.' },
      { role: :user, message: doc[:content] }
    ],
    temperature: 0.3
  
  output analysis: analysis[:content], doc_id: wf[:doc_id]
end
```

---

## Testing

DSL tests are in `spec/conductor/workflow/dsl/workflow_builder_spec.rb`:

```bash
bundle exec rspec spec/conductor/workflow/dsl/ --format documentation
```

Current coverage: 52 test cases covering:
- All basic task methods
- All LLM task methods
- Control flow (parallel, decide, loops)
- Reference resolution (OutputRef, InputRef)
- WorkflowDef conversion

---

## Related Documents

- [DESIGN.md](../../DESIGN.md) - High-level architecture
- [WORKER_DESIGN.md](WORKER_DESIGN.md) - Worker infrastructure
- [README.md](../../README.md) - User documentation
