# frozen_string_literal: true

module Conductor
  module Workflow
    # HttpPollTask makes HTTP calls and polls until a condition is met
    class HttpPollTask < TaskInterface
      # Create a new HttpPollTask
      # @param task_ref_name [String] Unique reference name for this task
      # @param http_input [HttpInput, Hash] HTTP request configuration
      # @param termination_condition [String] Condition expression for when to stop polling
      # @param polling_interval [Integer] Polling interval in seconds (default: 60)
      # @param polling_strategy [String] Polling strategy ('FIXED' or 'LINEAR_BACKOFF')
      def initialize(task_ref_name, http_input, termination_condition: nil, polling_interval: 60,
                     polling_strategy: 'FIXED')
        http_hash = case http_input
                    when HttpInput
                      http_input.to_h
                    when Hash
                      http_input['method'] ||= http_input[:method] || HttpMethod::GET
                      http_input
                    else
                      raise ArgumentError, "http_input must be an HttpInput or Hash, got #{http_input.class}"
                    end

        input_params = {
          'http_request' => http_hash,
          'pollingInterval' => polling_interval,
          'pollingStrategy' => polling_strategy
        }
        input_params['terminationCondition'] = termination_condition if termination_condition

        super(
          task_reference_name: task_ref_name,
          task_type: TaskType::HTTP_POLL,
          input_parameters: input_params
        )
      end
    end
  end
end
