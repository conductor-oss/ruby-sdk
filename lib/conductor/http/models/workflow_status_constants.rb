# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # WorkflowStatus constants and helper methods
      module WorkflowStatusConstants
        # Status values
        RUNNING = 'RUNNING'
        COMPLETED = 'COMPLETED'
        FAILED = 'FAILED'
        TIMED_OUT = 'TIMED_OUT'
        TERMINATED = 'TERMINATED'
        PAUSED = 'PAUSED'

        ALL = [RUNNING, COMPLETED, FAILED, TIMED_OUT, TERMINATED, PAUSED].freeze

        # Terminal statuses - workflow has ended
        TERMINAL_STATUSES = [COMPLETED, FAILED, TIMED_OUT, TERMINATED].freeze

        # Successful statuses
        SUCCESSFUL_STATUSES = [PAUSED, COMPLETED].freeze

        # Running statuses
        RUNNING_STATUSES = [RUNNING, PAUSED].freeze

        # Check if the given status is valid
        # @param [String] status The status to validate
        # @return [Boolean] true if valid, false otherwise
        def self.valid?(status)
          ALL.include?(status)
        end

        # Check if status is terminal (workflow has ended)
        # @param [String] status The status to check
        # @return [Boolean] true if terminal, false otherwise
        def self.terminal?(status)
          TERMINAL_STATUSES.include?(status)
        end

        # Check if status is successful
        # @param [String] status The status to check
        # @return [Boolean] true if successful, false otherwise
        def self.successful?(status)
          SUCCESSFUL_STATUSES.include?(status)
        end

        # Check if status is running
        # @param [String] status The status to check
        # @return [Boolean] true if running, false otherwise
        def self.running?(status)
          RUNNING_STATUSES.include?(status)
        end
      end
    end
  end
end
