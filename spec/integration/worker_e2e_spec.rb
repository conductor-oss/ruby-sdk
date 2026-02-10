# frozen_string_literal: true

require_relative 'integration_helper'

RSpec.describe 'Worker E2E Integration', :integration do
  let(:metadata_client) { IntegrationHelper.metadata_client }
  let(:workflow_client) { IntegrationHelper.workflow_client }
  let(:task_client) { IntegrationHelper.task_client }
  let(:configuration) { IntegrationHelper.configuration }

  # ==========================================
  # Full Worker Lifecycle E2E Test
  # ==========================================
  describe 'Complete worker lifecycle' do
    let(:task1_name) { IntegrationHelper.test_name('e2e_sync') }
    let(:task2_name) { IntegrationHelper.test_name('e2e_hash_return') }
    let(:task3_name) { IntegrationHelper.test_name('e2e_failing') }
    let(:workflow_name) { IntegrationHelper.test_name('e2e_worker_workflow') }

    before do
      # Register task definitions
      [task1_name, task2_name, task3_name].each do |tn|
        task_def = Conductor::Http::Models::TaskDef.new
        task_def.name = tn
        task_def.timeout_seconds = 60
        task_def.response_timeout_seconds = 30
        task_def.retry_count = 0
        metadata_client.register_task_def(task_def)
      end

      # Register a 3-task sequential workflow
      tasks = [
        build_workflow_task(task1_name, "#{task1_name}_ref"),
        build_workflow_task(task2_name, "#{task2_name}_ref"),
        build_workflow_task(task3_name, "#{task3_name}_ref")
      ]

      wf_def = Conductor::Http::Models::WorkflowDef.new
      wf_def.name = workflow_name
      wf_def.version = 1
      wf_def.description = 'Worker E2E test workflow'
      wf_def.tasks = tasks
      wf_def.schema_version = 2
      wf_def.timeout_seconds = 300
      wf_def.timeout_policy = 'TIME_OUT_WF'
      wf_def.owner_email = 'test@example.com'
      metadata_client.register_workflow_def(wf_def)
    end

    after do
      IntegrationHelper.cleanup_workflow_def(workflow_name, version: 1)
      [task1_name, task2_name, task3_name].each do |tn|
        IntegrationHelper.cleanup_task_def(tn)
      end
    end

    it 'executes a workflow end-to-end with workers using TaskHandler' do
      # Track events
      events_collected = []
      event_listener = EventCollector.new(events_collected)

      # Create workers
      worker1 = Conductor::Worker::Worker.new(task1_name, poll_interval: 100, thread_count: 1) do |task|
        # Simple sync worker that returns a TaskResult
        result = Conductor::Http::Models::TaskResult.complete
        result.output_data = {
          'worker' => 'sync_worker',
          'received_value' => task.input_data['value'],
          'timestamp' => Time.now.to_i
        }
        result
      end

      worker2 = Conductor::Worker::Worker.new(task2_name, poll_interval: 100, thread_count: 1) do |task|
        # Worker that returns a hash (auto-converted to COMPLETED)
        {
          'worker' => 'hash_worker',
          'received_value' => task.input_data['value'],
          'processed' => true
        }
      end

      worker3 = Conductor::Worker::Worker.new(task3_name, poll_interval: 100, thread_count: 1) do |task|
        raise Conductor::NonRetryableError, 'Intentional failure' if task.input_data['should_fail'] == true

        { 'worker' => 'conditional_worker', 'status' => 'ok' }
      end

      # Create TaskHandler
      handler = Conductor::Worker::TaskHandler.new(
        workers: [worker1, worker2, worker3],
        configuration: configuration,
        scan_for_annotated_workers: false,
        event_listeners: [event_listener],
        logger: Logger.new(nil) # Suppress log output in tests
      )

      begin
        # Start workers
        handler.start
        expect(handler.running?).to be true
        expect(handler.worker_names).to contain_exactly(task1_name, task2_name, task3_name)

        # Start a workflow that should succeed (task3 won't fail because should_fail is not true)
        workflow_id = workflow_client.start(
          workflow_name,
          input: { 'value' => 'e2e_test', 'should_fail' => false }
        )

        # Wait for completion
        wf = IntegrationHelper.wait_for_workflow(workflow_id, timeout: 30)

        # Assertions
        expect(wf.status).to eq(Conductor::Http::Models::WorkflowStatusConstants::COMPLETED)
        expect(wf.tasks).to be_an(Array)
        expect(wf.tasks.length).to eq(3)

        # Verify task 1 output
        task1 = wf.tasks.find { |t| t.reference_task_name == "#{task1_name}_ref" }
        expect(task1).not_to be_nil
        expect(task1.status).to eq('COMPLETED')
        expect(task1.output_data['worker']).to eq('sync_worker')

        # Verify task 2 output
        task2 = wf.tasks.find { |t| t.reference_task_name == "#{task2_name}_ref" }
        expect(task2).not_to be_nil
        expect(task2.status).to eq('COMPLETED')
        expect(task2.output_data['worker']).to eq('hash_worker')
        expect(task2.output_data['processed']).to eq(true)

        # Verify task 3 output
        task3 = wf.tasks.find { |t| t.reference_task_name == "#{task3_name}_ref" }
        expect(task3).not_to be_nil
        expect(task3.status).to eq('COMPLETED')

        # Verify events were collected
        # Note: Due to threading, we may need a small delay for events
        sleep(0.5)
        expect(events_collected).not_to be_empty

        # We should have at least some poll and execution events
        poll_events = events_collected.select { |e| e.is_a?(Conductor::Worker::Events::PollStarted) }
        exec_events = events_collected.select { |e| e.is_a?(Conductor::Worker::Events::TaskExecutionCompleted) }
        expect(poll_events.length).to be > 0
        expect(exec_events.length).to eq(3)
      ensure
        handler.stop(timeout: 5)
      end
    end

    it 'handles NonRetryableError correctly' do
      # Create a single worker for the first task
      worker = Conductor::Worker::Worker.new(task1_name, poll_interval: 100, thread_count: 1) do |_task|
        raise Conductor::NonRetryableError, 'Terminal failure'
      end

      # Register a single-task workflow
      single_wf_name = IntegrationHelper.test_name('e2e_fail_workflow')
      task = build_workflow_task(task1_name, "#{task1_name}_fail_ref")
      wf_def = Conductor::Http::Models::WorkflowDef.new
      wf_def.name = single_wf_name
      wf_def.version = 1
      wf_def.tasks = [task]
      wf_def.schema_version = 2
      wf_def.timeout_seconds = 300
      wf_def.timeout_policy = 'TIME_OUT_WF'
      wf_def.owner_email = 'test@example.com'
      metadata_client.register_workflow_def(wf_def)

      handler = Conductor::Worker::TaskHandler.new(
        workers: [worker],
        configuration: configuration,
        scan_for_annotated_workers: false,
        logger: Logger.new(nil)
      )

      begin
        handler.start

        workflow_id = workflow_client.start(single_wf_name, input: { 'value' => 'will_fail' })

        wf = IntegrationHelper.wait_for_workflow(workflow_id, timeout: 15)

        expect(wf.status).to eq(Conductor::Http::Models::WorkflowStatusConstants::FAILED)

        # The task should be FAILED_WITH_TERMINAL_ERROR
        failed_task = wf.tasks.find { |t| t.reference_task_name == "#{task1_name}_fail_ref" }
        expect(failed_task).not_to be_nil
        expect(failed_task.status).to eq('FAILED_WITH_TERMINAL_ERROR')
      ensure
        handler.stop(timeout: 5)
        IntegrationHelper.cleanup_workflow_def(single_wf_name, version: 1)
      end
    end
  end

  # ==========================================
  # Workflow DSL + Worker E2E
  # ==========================================
  describe 'Workflow DSL with workers' do
    let(:task_name) { IntegrationHelper.test_name('dsl_task') }

    before do
      task_def = Conductor::Http::Models::TaskDef.new
      task_def.name = task_name
      task_def.timeout_seconds = 60
      task_def.response_timeout_seconds = 30
      task_def.retry_count = 0
      metadata_client.register_task_def(task_def)
    end

    after do
      IntegrationHelper.cleanup_task_def(task_name)
    end

    it 'builds, registers, and executes a workflow using the DSL' do
      # Build workflow using DSL
      workflow = Conductor::Workflow::ConductorWorkflow.new(
        executor: Conductor::Workflow::WorkflowExecutor.new(IntegrationHelper.configuration)
      )

      dsl_wf_name = IntegrationHelper.test_name('dsl_workflow')

      workflow.name = dsl_wf_name
      workflow.version = 1
      workflow.description = 'DSL integration test'
      workflow.timeout_seconds = 300
      workflow.owner_email = 'test@example.com'

      # Add a simple task
      simple = Conductor::Workflow::SimpleTask.new(task_name, "#{task_name}_dsl_ref")
      simple.input('value', '${workflow.input.value}')

      workflow >> simple

      # Register the workflow
      wf_def = workflow.to_workflow_def
      metadata_client.register_workflow_def(wf_def, overwrite: true)

      # Create worker
      worker = Conductor::Worker::Worker.new(task_name, poll_interval: 100) do |task|
        { 'dsl_result' => "processed: #{task.input_data['value']}" }
      end

      handler = Conductor::Worker::TaskHandler.new(
        workers: [worker],
        configuration: configuration,
        scan_for_annotated_workers: false,
        logger: Logger.new(nil)
      )

      begin
        handler.start

        workflow_id = workflow_client.start(dsl_wf_name, input: { 'value' => 'dsl_test' })

        wf = IntegrationHelper.wait_for_workflow(workflow_id, timeout: 15)

        expect(wf.status).to eq(Conductor::Http::Models::WorkflowStatusConstants::COMPLETED)

        task_output = wf.tasks.first&.output_data
        expect(task_output).to include('dsl_result' => 'processed: dsl_test')
      ensure
        handler.stop(timeout: 5)
        IntegrationHelper.cleanup_workflow_def(dsl_wf_name, version: 1)
      end
    end
  end

  private

  def build_workflow_task(name, ref_name)
    task = Conductor::Http::Models::WorkflowTask.new
    task.name = name
    task.task_reference_name = ref_name
    task.type = 'SIMPLE'
    task.input_parameters = {
      'value' => '${workflow.input.value}',
      'should_fail' => '${workflow.input.should_fail}'
    }
    task
  end

  # Event collector for verifying events are published
  class EventCollector
    def initialize(events)
      @events = events
      @mutex = Mutex.new
    end

    def on_poll_started(event)
      @mutex.synchronize { @events << event }
    end

    def on_poll_completed(event)
      @mutex.synchronize { @events << event }
    end

    def on_poll_failure(event)
      @mutex.synchronize { @events << event }
    end

    def on_task_execution_started(event)
      @mutex.synchronize { @events << event }
    end

    def on_task_execution_completed(event)
      @mutex.synchronize { @events << event }
    end

    def on_task_execution_failure(event)
      @mutex.synchronize { @events << event }
    end

    def on_task_update_failure(event)
      @mutex.synchronize { @events << event }
    end
  end
end
