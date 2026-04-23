# frozen_string_literal: true

require_relative 'conductor_event'

module Conductor
  module Worker
    module Events
      # Base class for workflow lifecycle events
      # Carries the workflow name + version so canonical metrics can label by them
      class WorkflowEvent < ConductorEvent
        # @return [String] Workflow definition name
        attr_reader :workflow_type
        # @return [Integer, nil] Workflow version, if known
        attr_reader :version

        # @param workflow_type [String] Workflow definition name
        # @param version [Integer, nil] Workflow version
        def initialize(workflow_type:, version: nil)
          super()
          @workflow_type = workflow_type
          @version = version
        end

        def to_h
          super.merge(workflow_type: @workflow_type, version: @version)
        end
      end

      # Published when a StartWorkflow call fails client-side
      # Maps to canonical workflow_start_error_total{workflowType, exception}
      class WorkflowStartError < WorkflowEvent
        # @return [Exception] The exception that caused the failure
        attr_reader :cause

        # @param workflow_type [String] Workflow definition name
        # @param cause [Exception] The exception that caused the failure
        # @param version [Integer, nil] Workflow version
        def initialize(workflow_type:, cause:, version: nil)
          super(workflow_type: workflow_type, version: version)
          @cause = cause
        end

        def to_h
          super.merge(
            cause: @cause.class.name,
            cause_message: @cause.message
          )
        end
      end

      # Published after successfully serializing a workflow input payload
      # Carries the byte size for the canonical workflow_input_size_bytes gauge
      class WorkflowInputSize < WorkflowEvent
        # @return [Integer] Byte size of the serialized workflow input
        attr_reader :size_bytes

        # @param workflow_type [String] Workflow definition name
        # @param size_bytes [Integer] Byte size of serialized input
        # @param version [Integer, nil] Workflow version
        def initialize(workflow_type:, size_bytes:, version: nil)
          super(workflow_type: workflow_type, version: version)
          @size_bytes = size_bytes
        end

        def to_h
          super.merge(size_bytes: @size_bytes)
        end
      end
    end
  end
end
