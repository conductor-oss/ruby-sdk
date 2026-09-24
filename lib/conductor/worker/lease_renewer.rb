# frozen_string_literal: true

require 'concurrent'
require_relative '../http/models/task_result'

module Conductor
  module Worker
    # Renews a task's lease while its worker body runs. Each active task has one
    # interruptible heartbeat thread, independent of the polling/execution pool.
    class LeaseRenewer
      INTERVAL_FACTOR = 0.8

      def initialize(task_client:, logger:)
        @task_client = task_client
        @logger = logger
      end

      def during(task, worker_id:)
        interval = task.response_timeout_seconds.to_f * INTERVAL_FACTOR
        return yield unless interval.positive?

        stopped = Concurrent::Event.new
        heartbeat = Thread.new do
          Thread.current.name = "conductor-lease-#{task.task_id}"
          delay = interval
          # Retry transient failures within the remaining lease window.
          delay = renew(task, worker_id) ? interval : [interval / 4, 1.0].min until stopped.wait(delay)
        end
        yield
      ensure
        stopped&.set
        # Drain an in-flight heartbeat before the caller can submit a final result.
        heartbeat&.join
      end

      private

      def renew(task, worker_id)
        result = Http::Models::TaskResult.new(
          task_id: task.task_id,
          workflow_instance_id: task.workflow_instance_id,
          worker_id: worker_id,
          status: Http::Models::TaskResultStatus::IN_PROGRESS,
          extend_lease: true
        )
        # The original endpoint handles lease updates without claiming more work.
        @task_client.update_task(result)
        true
      rescue StandardError => e
        @logger.warn("Lease renewal failed for task #{task.task_id}: #{e.class}: #{e.message}")
        false
      end
    end
  end
end
