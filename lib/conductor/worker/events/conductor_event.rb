# frozen_string_literal: true

module Conductor
  module Worker
    module Events
      # Base class for all Conductor events
      # Provides a timestamp for when the event occurred
      class ConductorEvent
        # @return [Time] UTC timestamp when event was created
        attr_reader :timestamp

        def initialize
          @timestamp = Time.now.utc
        end

        # @return [Hash] Event as a hash for serialization
        def to_h
          { timestamp: @timestamp.iso8601(3) }
        end
      end

      # Base class for task runner events
      # All events related to task polling and execution inherit from this
      class TaskRunnerEvent < ConductorEvent
        # @return [String] The task type/definition name
        attr_reader :task_type

        # @param task_type [String] Task definition name
        def initialize(task_type:)
          super()
          @task_type = task_type
        end

        def to_h
          super.merge(task_type: @task_type)
        end
      end
    end
  end
end
