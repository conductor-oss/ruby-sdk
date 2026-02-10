# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # TaskResultStatus enum representing the status of task execution
      module TaskResultStatus
        COMPLETED = 'COMPLETED'
        FAILED = 'FAILED'
        FAILED_WITH_TERMINAL_ERROR = 'FAILED_WITH_TERMINAL_ERROR'
        IN_PROGRESS = 'IN_PROGRESS'

        ALL = [COMPLETED, FAILED, FAILED_WITH_TERMINAL_ERROR, IN_PROGRESS].freeze

        # Check if the given status is valid
        # @param [String] status The status to validate
        # @return [Boolean] true if valid, false otherwise
        def self.valid?(status)
          ALL.include?(status)
        end
      end
    end
  end
end
