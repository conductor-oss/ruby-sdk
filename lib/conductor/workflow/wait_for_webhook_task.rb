# frozen_string_literal: true

module Conductor
  module Workflow
    # WaitForWebhookTask waits for an external webhook callback
    # The task stays in IN_PROGRESS until a webhook request matches the configured criteria
    class WaitForWebhookTask < TaskInterface
      # Create a new WaitForWebhookTask
      # @param task_ref_name [String] Unique reference name for this task
      # @param matches [Hash] Match conditions for the webhook payload
      def initialize(task_ref_name, matches: {})
        super(
          task_reference_name: task_ref_name,
          task_type: TaskType::WAIT_FOR_WEBHOOK,
          input_parameters: { 'matches' => matches }
        )
      end
    end
  end
end
