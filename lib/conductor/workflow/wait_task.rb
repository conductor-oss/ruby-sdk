# frozen_string_literal: true

module Conductor
  module Workflow
    # WaitTask pauses workflow execution until a condition is met
    # Can wait for a specific time, duration, or external signal
    class WaitTask < TaskInterface
      # Create a new WaitTask
      # @param task_ref_name [String] Unique reference name for this task
      # @param wait_until [String, nil] Specific date/time to wait until (e.g., '2024-12-25 05:25 PST')
      # @param wait_for_seconds [Integer, nil] Duration to wait in seconds
      # @note Only one of wait_until or wait_for_seconds should be provided
      # @example Wait for duration
      #   wait = WaitTask.new('pause_task', wait_for_seconds: 60)
      # @example Wait until specific time
      #   wait = WaitTask.new('scheduled_task', wait_until: '2024-12-25 09:00 UTC')
      def initialize(task_ref_name, wait_until: nil, wait_for_seconds: nil)
        super(
          task_reference_name: task_ref_name,
          task_type: TaskType::WAIT
        )

        raise ArgumentError, 'Only one of wait_until or wait_for_seconds should be provided' if wait_until && wait_for_seconds

        if wait_until
          @input_parameters = { 'wait_until' => wait_until }
        elsif wait_for_seconds
          @input_parameters = { 'duration' => "#{wait_for_seconds}s" }
        end
        # If neither provided, wait indefinitely until signaled
      end
    end

    # WaitForDurationTask waits for a specific duration
    class WaitForDurationTask < WaitTask
      # Create a task that waits for a duration
      # @param task_ref_name [String] Unique reference name for this task
      # @param duration_seconds [Integer] Duration to wait in seconds
      def initialize(task_ref_name, duration_seconds)
        super(task_ref_name)
        @input_parameters = { 'duration' => "#{duration_seconds}s" }
      end
    end

    # WaitUntilTask waits until a specific date/time
    class WaitUntilTask < WaitTask
      # Create a task that waits until a specific time
      # @param task_ref_name [String] Unique reference name for this task
      # @param date_time [String] Date/time to wait until
      def initialize(task_ref_name, date_time)
        super(task_ref_name)
        @input_parameters = { 'until' => date_time }
      end
    end
  end
end
