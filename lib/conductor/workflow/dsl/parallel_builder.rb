# frozen_string_literal: true

module Conductor
  module Workflow
    module Dsl
      # ParallelBuilder collects tasks defined in a parallel block.
      # It proxies all method calls to the parent WorkflowBuilder and
      # organizes the resulting tasks into parallel branches.
      #
      # @example
      #   parallel do
      #     simple :task1
      #     simple :task2
      #   end
      #
      class ParallelBuilder
        def initialize(parent_builder)
          @parent = parent_builder
          @branches = []
          @current_branch = []
        end

        # Finalize the parallel block and return branches
        # @return [Array<Array<TaskRef>>] Array of task branches
        def finalize
          # Add current branch if it has tasks
          @branches << @current_branch unless @current_branch.empty?
          @branches
        end

        # Delegate all method calls to the parent builder
        # and collect resulting TaskRefs
        def method_missing(name, *args, **kwargs, &block)
          if @parent.respond_to?(name, true)
            task_ref = @parent.send(name, *args, **kwargs, &block)
            @current_branch << task_ref if task_ref.is_a?(TaskRef)
            task_ref
          else
            super
          end
        end

        def respond_to_missing?(name, include_private = false)
          @parent.respond_to?(name, include_private) || super
        end
      end
    end
  end
end
