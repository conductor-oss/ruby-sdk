# Conductor Ruby SDK

Official Ruby SDK for [Conductor OSS](https://github.com/conductor-oss/conductor) - a durable workflow orchestration engine.

[![Gem Version](https://badge.fury.io/rb/conductor_ruby.svg)](https://badge.fury.io/rb/conductor_ruby)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

## Features

- **Full Feature Parity** with Python SDK
- **Workflow DSL** - Build workflows programmatically with 25+ task types
- **Worker Framework** - Multi-threaded task execution with class-based and block-based workers
- **LLM/AI Tasks** - Chat completion, embeddings, RAG, image/audio generation
- **Orkes Cloud Support** - Authentication, secrets, integrations, prompts
- **Comprehensive Testing** - 281 unit tests, 110 integration tests

## Installation

Add to your Gemfile:

```ruby
gem 'conductor_ruby'
```

Or install directly:

```bash
gem install conductor_ruby
```

## Quick Start

### Hello World

```ruby
require 'conductor'

# Configuration (reads CONDUCTOR_SERVER_URL from environment)
config = Conductor::Configuration.new

# Create clients
clients = Conductor::Orkes::OrkesClients.new(config)
workflow_executor = clients.get_workflow_executor

# Define a worker
class GreetWorker
  include Conductor::Worker::WorkerModule
  worker_task 'greet'

  def execute(task)
    name = get_input(task, 'name', 'World')
    { 'result' => "Hello, #{name}!" }
  end
end

# Build workflow using DSL
include Conductor::Workflow

workflow = ConductorWorkflow.new(clients.get_workflow_client, 'greetings', version: 1, executor: workflow_executor)
greet = SimpleTask.new('greet', 'greet_ref').input('name', workflow.input('name'))
workflow >> greet
workflow.output_parameter('result', greet.output('result'))

# Register and execute
workflow_executor.register_workflow(workflow, overwrite: true)

# Start workers
runner = Conductor::Worker::TaskRunner.new(config)
runner.register_worker(GreetWorker.new)
runner.start

# Execute workflow
result = workflow_executor.execute('greetings', input: { 'name' => 'Ruby' }, wait_for_seconds: 30)
puts "Result: #{result.output['result']}"  # => "Hello, Ruby!"

runner.stop
```

## Examples

The `examples/` directory contains comprehensive examples matching the Python SDK:

| Example | Description |
|---------|-------------|
| [`helloworld/`](examples/helloworld/) | Simplest complete example - worker + workflow + execution |
| [`simple_worker.rb`](examples/simple_worker.rb) | Worker patterns: class-based, block-based, error handling |
| [`simple_workflow.rb`](examples/simple_workflow.rb) | Basic workflow client usage |
| [`workflow_dsl.rb`](examples/workflow_dsl.rb) | Comprehensive DSL: Fork/Join, Switch, HTTP, Sub-workflows |
| [`dynamic_workflow.rb`](examples/dynamic_workflow.rb) | Create and execute workflows at runtime |
| [`kitchensink.rb`](examples/kitchensink.rb) | All major task types: HTTP, JavaScript, JQ, Switch, Wait, Terminate |
| [`workflow_ops.rb`](examples/workflow_ops.rb) | Lifecycle operations: pause, resume, restart, retry, rerun, search |

Run examples:

```bash
# Set environment variables
export CONDUCTOR_SERVER_URL=http://localhost:8080/api
# For Orkes Cloud:
# export CONDUCTOR_AUTH_KEY=your_key
# export CONDUCTOR_AUTH_SECRET=your_secret

# Run hello world
cd examples/helloworld && bundle exec ruby helloworld.rb

# Run other examples
bundle exec ruby examples/dynamic_workflow.rb
bundle exec ruby examples/kitchensink.rb
bundle exec ruby examples/workflow_ops.rb
```

## Workflow DSL

Build workflows programmatically with Ruby:

```ruby
include Conductor::Workflow

workflow = ConductorWorkflow.new(client, 'my_workflow', version: 1)

# Sequential tasks
task1 = SimpleTask.new('task1', 'ref1').input('key', 'value')
task2 = SimpleTask.new('task2', 'ref2')
workflow >> task1 >> task2

# Parallel execution (Fork/Join)
workflow >> [[branch1_task], [branch2_task]]

# Conditional branching
switch = SwitchTask.new('decide', '${workflow.input.type}')
  .switch_case('A', [handle_a])
  .switch_case('B', [handle_b])
  .default_case([handle_default])
workflow >> switch

# HTTP calls
http = HttpTask.new('call_api', {
  'uri' => 'https://api.example.com/data',
  'method' => 'POST',
  'body' => { 'key' => '${workflow.input.value}' }
})

# Sub-workflows
sub = SubWorkflowTask.new('call_child', 'child_workflow', version: 1)
  .input('data', '${previous_task.output}')
```

### Available Task Types (25+)

**Control Flow:** SimpleTask, SwitchTask, ForkTask, JoinTask, DoWhileTask, DynamicTask, DynamicForkTask, SubWorkflowTask

**System Tasks:** HttpTask, HttpPollTask, EventTask, WaitTask, WaitForWebhookTask, TerminateTask, SetVariableTask, JsonJqTask, JavascriptTask, KafkaPublishTask, StartWorkflowTask, HumanTask

**LLM/AI Tasks:** LlmChatCompleteTask, LlmTextCompleteTask, LlmGenerateEmbeddingsTask, LlmIndexTextTask, LlmSearchIndexTask, GenerateImageTask, GenerateAudioTask, and more

## Worker Framework

### Class-Based Workers

```ruby
class ImageProcessor
  include Conductor::Worker::WorkerModule

  worker_task 'process_image', poll_interval: 1, thread_count: 4

  def execute(task)
    url = get_input(task, 'image_url')
    # Process image...
    
    result = Conductor::Http::Models::TaskResult.complete
    result.add_output_data('processed_url', processed_url)
    result.log('Image processed successfully')
    result
  end
end
```

### Block-Based Workers

```ruby
worker = Conductor::Worker.define('simple_task') do |task|
  input = task.input_data['value']
  { result: input * 2 }  # Return hash for automatic TaskResult
end
```

### Running Workers

```ruby
runner = Conductor::Worker::TaskRunner.new(config)
runner.register_worker(ImageProcessor.new)
runner.register_worker(worker)
runner.start(threads: 4)

# Graceful shutdown
trap('INT') { runner.stop }
sleep while runner.running?
```

## Configuration

### Environment Variables

```bash
export CONDUCTOR_SERVER_URL=http://localhost:8080/api
export CONDUCTOR_AUTH_KEY=your_key        # For Orkes Cloud
export CONDUCTOR_AUTH_SECRET=your_secret  # For Orkes Cloud
```

### Programmatic

```ruby
config = Conductor::Configuration.new(
  server_api_url: 'https://play.orkes.io/api',
  auth_key: 'your_key',
  auth_secret: 'your_secret',
  auth_token_ttl_min: 45,
  verify_ssl: true
)
```

## API Coverage

### Resource APIs (17 classes)

| API | Description |
|-----|-------------|
| WorkflowResourceApi | Workflow execution and management |
| TaskResourceApi | Task polling and updates |
| MetadataResourceApi | Workflow/task definitions |
| SchedulerResourceApi | Scheduled workflows |
| EventResourceApi | Event handlers |
| WorkflowBulkResourceApi | Bulk operations |
| PromptResourceApi | AI prompt templates |
| SecretResourceApi | Secret management |
| IntegrationResourceApi | External integrations |
| + 8 more | Authorization, Users, Groups, Roles, etc. |

### High-Level Clients (9 classes)

```ruby
clients = Conductor::Orkes::OrkesClients.new(config)

workflow_client = clients.get_workflow_client
task_client = clients.get_task_client
metadata_client = clients.get_metadata_client
scheduler_client = clients.get_scheduler_client
prompt_client = clients.get_prompt_client
secret_client = clients.get_secret_client
authorization_client = clients.get_authorization_client
workflow_executor = clients.get_workflow_executor
```

## Testing

```bash
# Unit tests
bundle exec rspec spec/conductor/

# Integration tests (requires Conductor server)
CONDUCTOR_SERVER_URL=http://localhost:8080/api bundle exec rspec spec/integration/
```

## Requirements

- Ruby 2.6+ (Ruby 3+ recommended)
- Conductor OSS 3.x or Orkes Cloud

## Dependencies

- `faraday ~> 2.0` - HTTP client
- `faraday-net_http_persistent ~> 2.0` - Connection pooling
- `faraday-retry ~> 2.0` - Automatic retries
- `concurrent-ruby ~> 1.2` - Thread-safe concurrency

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Run tests (`bundle exec rspec`)
4. Commit your changes (`git commit -m 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

## License

Apache 2.0 - see [LICENSE](LICENSE) for details.

## Links

- [Conductor OSS](https://github.com/conductor-oss/conductor)
- [Orkes Cloud](https://orkes.io)
- [Documentation](https://conductor-oss.org)
- [Python SDK](https://github.com/conductor-sdk/conductor-python)
- [Community Slack](https://join.slack.com/t/orkes-conductor/shared_invite/zt-2vdbx239s-Eacdyqya9giNLHfrCavfaA)
