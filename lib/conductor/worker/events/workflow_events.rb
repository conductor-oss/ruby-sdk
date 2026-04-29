# frozen_string_literal: true

require_relative 'conductor_event'

module Conductor
  module Worker
    module Events
      class WorkflowEvent < ConductorEvent
        attr_reader :workflow_type, :version

        def initialize(workflow_type:, version: nil)
          super()
          @workflow_type = workflow_type
          @version = version
        end

        def to_h
          super.merge(workflow_type: @workflow_type, version: @version)
        end
      end

      class WorkflowStartError < WorkflowEvent
        attr_reader :cause

        def initialize(workflow_type:, cause:, version: nil)
          super(workflow_type: workflow_type, version: version)
          @cause = cause
        end

        def to_h
          super.merge(cause: @cause.class.name, cause_message: @cause.message)
        end
      end

      class WorkflowInputSize < WorkflowEvent
        attr_reader :size_bytes

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
