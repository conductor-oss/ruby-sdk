# frozen_string_literal: true

module Conductor
  module Worker
    # Return type for long-running tasks
    # When a worker returns TaskInProgress, the task remains in IN_PROGRESS state
    # and Conductor will poll again after callback_after_seconds
    #
    # @example Long-running task with periodic updates
    #   def execute(task)
    #     ctx = TaskContext.current
    #
    #     # Check if we're being polled again
    #     if ctx.poll_count > 0
    #       # Check if processing is complete
    #       if processing_complete?(task.input_data['job_id'])
    #         return { status: 'completed', result: get_result() }
    #       end
    #
    #       # Still processing, check back later
    #       return TaskInProgress.new(
    #         callback_after_seconds: 30,
    #         output: { status: 'processing', progress: get_progress() }
    #       )
    #     end
    #
    #     # First poll - start the long-running job
    #     job_id = start_long_running_job(task.input_data)
    #
    #     TaskInProgress.new(
    #       callback_after_seconds: 60,
    #       output: { status: 'started', job_id: job_id }
    #     )
    #   end
    class TaskInProgress
      # @return [Integer] Seconds to wait before Conductor polls again
      attr_accessor :callback_after_seconds

      # @return [Hash, nil] Intermediate output data
      attr_accessor :output

      # Create a TaskInProgress response
      # @param callback_after_seconds [Integer] Seconds to wait before polling again (default: 60)
      # @param output [Hash, nil] Intermediate output data (optional)
      def initialize(callback_after_seconds: 60, output: nil)
        @callback_after_seconds = callback_after_seconds
        @output = output
      end

      # Convert to hash
      # @return [Hash]
      def to_h
        {
          callback_after_seconds: @callback_after_seconds,
          output: @output
        }
      end
    end
  end
end
