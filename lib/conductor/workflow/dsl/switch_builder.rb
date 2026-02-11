# frozen_string_literal: true

module Conductor
  module Workflow
    module Dsl
      # SwitchBuilder collects switch cases defined in a decide block.
      # It provides on() and otherwise() methods for defining case branches.
      #
      # @example
      #   decide user[:country] do
      #     on 'US' do
      #       simple :us_flow
      #     end
      #     on 'UK' do
      #       simple :uk_flow
      #     end
      #     otherwise do
      #       simple :default_flow
      #     end
      #   end
      #
      class SwitchBuilder
        attr_reader :expression, :cases, :default

        def initialize(expression, parent_builder)
          @expression = expression
          @parent = parent_builder
          @cases = {}
          @default = []
        end

        # Define a case branch
        # @param value [String, Symbol] The case value to match
        # @yield Block containing tasks for this case
        def on(value, &block)
          tasks = []
          collector = TaskCollector.new(@parent, tasks)
          collector.instance_eval(&block)
          @cases[value.to_s] = tasks
        end

        # Define the default case (executed if no cases match)
        # @yield Block containing tasks for the default case
        def otherwise(&block)
          collector = TaskCollector.new(@parent, @default)
          collector.instance_eval(&block)
        end
      end

      # TaskCollector is a helper that collects tasks created in a block.
      # It delegates method calls to the parent builder and stores the results.
      class TaskCollector
        def initialize(parent_builder, task_array)
          @parent = parent_builder
          @tasks = task_array
        end

        def method_missing(name, *args, **kwargs, &block)
          if @parent.respond_to?(name, true)
            task_ref = @parent.send(name, *args, **kwargs, &block)
            @tasks << task_ref if task_ref.is_a?(TaskRef)
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
