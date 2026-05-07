# frozen_string_literal: true

module Harness
  # WorkflowGovernor -- starts a configurable number of workflow instances
  # per second in a background thread, feeding work to the simulated workers.
  class WorkflowGovernor
    def initialize(workflow_executor, workflow_name, workflows_per_second)
      @workflow_executor = workflow_executor
      @workflow_name = workflow_name
      @workflows_per_second = workflows_per_second
      @running = false
      @thread = nil
    end

    def start
      @running = true
      puts "WorkflowGovernor started: workflow=#{@workflow_name}, rate=#{@workflows_per_second}/sec"

      @thread = Thread.new { run_loop }
      @thread.name = 'workflow-governor'
      self
    end

    def stop
      @running = false
      @thread&.join(5)
      puts 'WorkflowGovernor stopped'
    end

    private

    def run_loop
      while @running
        start_batch
        sleep(1)
      end
    end

    def start_batch
      @workflows_per_second.times do
        request = Conductor::Http::Models::StartWorkflowRequest.new(name: @workflow_name, version: 1)
        @workflow_executor.start_workflow(request)
      end
      puts "Governor: started #{@workflows_per_second} workflow(s)"
    rescue StandardError => e
      puts "Governor: error starting workflows: #{e.message}"
    end
  end
end
