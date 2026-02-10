# frozen_string_literal: true

module Conductor
  module Workflow
    # EventTask publishes events to external systems
    # Base class for different event sink types
    class EventTask < TaskInterface
      attr_accessor :sink

      # Create a new EventTask
      # @param task_ref_name [String] Unique reference name for this task
      # @param event_prefix [String] Event sink prefix (e.g., 'sqs', 'conductor')
      # @param event_suffix [String] Event sink suffix (e.g., queue name, event name)
      def initialize(task_ref_name, event_prefix, event_suffix)
        super(
          task_reference_name: task_ref_name,
          task_type: TaskType::EVENT
        )
        @sink = "#{event_prefix}:#{event_suffix}"
      end

      # Convert to WorkflowTask
      # @return [Conductor::Http::Models::WorkflowTask]
      def to_workflow_task
        workflow_task = super
        workflow_task.sink = @sink
        workflow_task
      end
    end

    # SqsEventTask publishes events to AWS SQS
    class SqsEventTask < EventTask
      # Create a new SqsEventTask
      # @param task_ref_name [String] Unique reference name for this task
      # @param queue_name [String] SQS queue name
      # @example
      #   sqs = SqsEventTask.new('notify_queue', 'my-notification-queue')
      #   sqs.input('message', '${workflow.input.notification}')
      def initialize(task_ref_name, queue_name)
        super(task_ref_name, 'sqs', queue_name)
      end
    end

    # ConductorEventTask publishes events to Conductor's internal event system
    class ConductorEventTask < EventTask
      # Create a new ConductorEventTask
      # @param task_ref_name [String] Unique reference name for this task
      # @param event_name [String] Conductor event name
      # @example
      #   event = ConductorEventTask.new('publish_event', 'order_completed')
      #   event.input('orderId', '${workflow.input.orderId}')
      def initialize(task_ref_name, event_name)
        super(task_ref_name, 'conductor', event_name)
      end
    end
  end
end
