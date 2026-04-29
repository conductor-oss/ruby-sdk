# frozen_string_literal: true

# Load the SDK from source (relative to repo root)
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'conductor'
require 'conductor/worker/telemetry/prometheus_backend'
require_relative 'simulated_task_worker'
require_relative 'workflow_governor'

module Harness
  WORKFLOW_NAME = 'ruby_simulated_tasks_workflow'

  SIMULATED_WORKERS = [
    { task_name: 'ruby_worker_0', codename: 'quickpulse',  sleep_seconds: 1 },
    { task_name: 'ruby_worker_1', codename: 'whisperlink', sleep_seconds: 2 },
    { task_name: 'ruby_worker_2', codename: 'shadowfetch', sleep_seconds: 3 },
    { task_name: 'ruby_worker_3', codename: 'ironforge',   sleep_seconds: 4 },
    { task_name: 'ruby_worker_4', codename: 'deepcrawl',   sleep_seconds: 5 }
  ].freeze

  def self.env_int(name, default)
    val = ENV.fetch(name, nil)
    val ? Integer(val) : default
  rescue ArgumentError
    default
  end

  def self.main
    $stdout.sync = true

    workflows_per_sec = env_int('HARNESS_WORKFLOWS_PER_SEC', 2)
    batch_size        = env_int('HARNESS_BATCH_SIZE', 20)
    poll_interval_ms  = env_int('HARNESS_POLL_INTERVAL_MS', 100)

    metrics_port = env_int('HARNESS_METRICS_PORT', 9991)

    configuration = Conductor::Configuration.new
    register_metadata(configuration)

    metrics_collector = Conductor::Worker::Telemetry::MetricsCollector.create(backend: :prometheus)
    metrics_server = Conductor::Worker::Telemetry::MetricsServer.new(port: metrics_port)
    metrics_server.start
    puts "Prometheus metrics server started on port #{metrics_port}"

    workers = SIMULATED_WORKERS.map do |def_entry|
      sim = SimulatedTaskWorker.new(
        def_entry[:task_name],
        def_entry[:codename],
        def_entry[:sleep_seconds],
        batch_size: batch_size,
        poll_interval_ms: poll_interval_ms
      )

      Conductor::Worker::Worker.new(
        def_entry[:task_name],
        sim.method(:execute),
        poll_interval: poll_interval_ms,
        thread_count: batch_size,
        worker_id: sim.worker_id
      )
    end

    task_handler = Conductor::Worker::TaskHandler.new(
      workers: workers,
      configuration: configuration,
      scan_for_annotated_workers: false,
      event_listeners: [metrics_collector]
    )
    task_handler.start

    workflow_executor = Conductor::Workflow::WorkflowExecutor.new(
      configuration,
      event_dispatcher: task_handler.event_dispatcher
    )
    governor = WorkflowGovernor.new(workflow_executor, WORKFLOW_NAME, workflows_per_sec)
    governor.start

    shutdown = proc do
      puts 'Shutting down...'
      governor.stop
      task_handler.stop
      exit(0)
    end

    trap('INT',  &shutdown)
    trap('TERM', &shutdown)

    task_handler.join
  end

  def self.register_metadata(configuration)
    metadata_client = Conductor::Client::MetadataClient.new(configuration)

    task_defs = SIMULATED_WORKERS.map do |entry|
      Conductor::Http::Models::TaskDef.new(
        name: entry[:task_name],
        description: "Ruby SDK harness simulated task (#{entry[:codename]}, default delay #{entry[:sleep_seconds]}s)",
        retry_count: 1,
        timeout_seconds: 300,
        response_timeout_seconds: 300
      )
    end
    metadata_client.register_task_defs(task_defs)

    workflow_tasks = SIMULATED_WORKERS.map do |entry|
      Conductor::Http::Models::WorkflowTask.new(
        name: entry[:task_name],
        task_reference_name: entry[:codename],
        type: 'SIMPLE'
      )
    end

    workflow_def = Conductor::Http::Models::WorkflowDef.new(
      name: WORKFLOW_NAME,
      version: 1,
      description: 'Ruby SDK harness simulated task workflow',
      owner_email: 'ruby-sdk-harness@conductor.io',
      tasks: workflow_tasks
    )
    metadata_client.update_workflow_def(workflow_def)

    puts "Registered workflow #{WORKFLOW_NAME} with #{SIMULATED_WORKERS.size} tasks"
  end
end

Harness.main
