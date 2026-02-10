# frozen_string_literal: true

module Conductor
  module Workflow
    # Timeout policy for workflows and tasks
    module TimeoutPolicy
      # Workflow times out and is marked as TIMED_OUT
      TIME_OUT_WORKFLOW = 'TIME_OUT_WF'

      # Only send an alert, workflow continues
      ALERT_ONLY = 'ALERT_ONLY'

      # All valid timeout policies
      ALL_POLICIES = [TIME_OUT_WORKFLOW, ALERT_ONLY].freeze

      # Check if a timeout policy is valid
      # @param policy [String] The policy to check
      # @return [Boolean] true if valid
      def self.valid?(policy)
        ALL_POLICIES.include?(policy)
      end
    end

    # Evaluator types for switch tasks and expressions
    module EvaluatorType
      JAVASCRIPT = 'javascript'
      ECMASCRIPT = 'graaljs'
      VALUE_PARAM = 'value-param'
    end
  end
end
