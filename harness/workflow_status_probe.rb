# frozen_string_literal: true

module Harness
  MAX_TRACKED_IDS = 256

  # WorkflowStatusProbe exercises UUID-bearing workflow lookup endpoints so
  # http_api_client_request_seconds picks up entries with
  # uri=/workflow/{workflowId} and uri=/workflow/{workflowId}/status.
  #
  # Default harness traffic only hits bounded, no-path-param URLs (poll/update),
  # making the high-cardinality concern on the uri label invisible without this
  # probe.
  #
  # Default off. Runs only when HARNESS_PROBE_RATE_PER_SEC > 0.
  # Side-effect-free: only issues read calls (get_execution_status, get_workflow_status).
  # Self-bounded: fixed-size FIFO of workflow IDs.
  class WorkflowStatusProbe
    def initialize(workflow_client, calls_per_second)
      @workflow_client = workflow_client
      @calls_per_second = calls_per_second
      @recent_ids = []
      @mutex = Mutex.new
      @rng = Random.new
      @running = false
      @thread = nil
    end

    # Capture a workflow ID for later probing. Thread-safe.
    def offer(workflow_id)
      return if workflow_id.nil? || workflow_id.empty?

      @mutex.synchronize do
        @recent_ids << workflow_id
        @recent_ids.shift(@recent_ids.size - MAX_TRACKED_IDS) if @recent_ids.size > MAX_TRACKED_IDS
      end
    end

    def start
      if @calls_per_second <= 0
        puts 'WorkflowStatusProbe disabled (HARNESS_PROBE_RATE_PER_SEC<=0)'
        return self
      end

      @running = true
      puts "WorkflowStatusProbe started: rate=#{@calls_per_second}/sec, retainedIds<=#{MAX_TRACKED_IDS}"

      @thread = Thread.new { run_loop }
      @thread.name = 'workflow-status-probe'
      self
    end

    def stop
      @running = false
      @thread&.join(5)
      puts 'WorkflowStatusProbe stopped'
    end

    private

    def run_loop
      while @running
        tick
        sleep(1)
      end
    end

    def tick
      ids = @mutex.synchronize do
        budget = [@calls_per_second, @recent_ids.size].min
        return if budget.zero?

        Array.new(budget) { @recent_ids[@rng.rand(@recent_ids.size)] }
      end

      ids.each do |id|
        if @rng.rand < 0.5
          @workflow_client.workflow_api.get_execution_status(id, include_tasks: false)
        else
          @workflow_client.workflow_api.get_workflow_status(id)
        end
      rescue StandardError => e
        puts "probe: #{id}: #{e.message}"
      end
    end
  end
end
