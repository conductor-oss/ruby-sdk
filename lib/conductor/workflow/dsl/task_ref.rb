# frozen_string_literal: true

module Conductor
  module Workflow
    module Dsl
      # TaskRef is a lightweight proxy returned by DSL task methods
      # Enables [] syntax for output references and stores task metadata
      class TaskRef
        attr_reader :ref_name, :task_name, :task_type, :input_parameters, :options
        alias inputs input_parameters

        # @param ref_name [String] Auto-generated reference name
        # @param task_name [String] The task definition name
        # @param task_type [String] Conductor task type (SIMPLE, HTTP, etc.)
        # @param input_parameters [Hash] Input parameters for the task
        # @param options [Hash] Additional options (optional, cache, retry, etc.)
        def initialize(ref_name:, task_name:, task_type:, input_parameters: {}, options: {})
          @ref_name = ref_name
          @task_name = task_name
          @task_type = task_type
          @input_parameters = input_parameters
          @options = options
        end

        # Access task output by field name using [] syntax
        # @param field [String, Symbol] The output field name
        # @return [OutputRef] An OutputRef pointing to this task's output
        # @example
        #   user = simple :get_user, id: 1
        #   user[:email] # => "${get_user_ref.output.email}"
        #   user[:profile][:name] # => "${get_user_ref.output.profile.name}"
        def [](field)
          OutputRef.new("#{@ref_name}.output.#{field}")
        end

        # Access task's full output (no specific field)
        # @return [OutputRef] An OutputRef pointing to all task output
        def output
          OutputRef.new("#{@ref_name}.output")
        end

        # Access task input (for dynamic references)
        # @param field [String, Symbol, nil] Optional field name
        # @return [OutputRef] An OutputRef pointing to task input
        def input(field = nil)
          if field
            OutputRef.new("#{@ref_name}.input.#{field}")
          else
            OutputRef.new("#{@ref_name}.input")
          end
        end

        # Convert to WorkflowTask model for serialization
        # @return [Conductor::Http::Models::WorkflowTask]
        def to_workflow_task
          wf_task = Conductor::Http::Models::WorkflowTask.new(
            name: @task_name,
            task_reference_name: @ref_name,
            type: @task_type,
            input_parameters: @input_parameters
          )

          # Apply options
          wf_task.description = @options[:description] if @options[:description]
          wf_task.optional = @options[:optional] if @options[:optional]

          # Cache config
          if @options[:cache_key] && @options[:cache_ttl]
            wf_task.cache_config = Conductor::Http::Models::CacheConfig.new(
              key: @options[:cache_key],
              ttl_in_second: @options[:cache_ttl]
            )
          end

          # Task-specific fields
          apply_task_specific_fields(wf_task)

          wf_task
        end

        private

        def apply_task_specific_fields(wf_task)
          case @task_type
          when Conductor::Workflow::TaskType::SWITCH
            apply_switch_fields(wf_task)
          when Conductor::Workflow::TaskType::FORK_JOIN
            apply_fork_join_fields(wf_task)
          when Conductor::Workflow::TaskType::JOIN
            apply_join_fields(wf_task)
          when Conductor::Workflow::TaskType::DO_WHILE
            apply_do_while_fields(wf_task)
          when Conductor::Workflow::TaskType::SUB_WORKFLOW
            apply_sub_workflow_fields(wf_task)
          when Conductor::Workflow::TaskType::FORK_JOIN_DYNAMIC
            apply_dynamic_fork_fields(wf_task)
          when Conductor::Workflow::TaskType::DYNAMIC
            wf_task.dynamic_task_name_param = @options[:dynamic_task_name_param]
          when Conductor::Workflow::TaskType::EVENT
            wf_task.sink = @options[:sink]
          when Conductor::Workflow::TaskType::INLINE
            wf_task.expression = @options[:expression]
            wf_task.evaluator_type = @options[:evaluator_type] || 'javascript'
          when Conductor::Workflow::TaskType::JSON_JQ_TRANSFORM
            wf_task.expression = @options[:query_expression]
            wf_task.evaluator_type = 'graaljs' if @options[:query_expression]
          end
        end

        def apply_switch_fields(wf_task)
          wf_task.evaluator_type = 'value-param'
          wf_task.expression = @options[:expression]

          # Convert decision_cases from TaskRef arrays to WorkflowTask arrays
          if @options[:decision_cases]
            wf_task.decision_cases = @options[:decision_cases].transform_values do |task_refs|
              task_refs.map { |tr| tr.is_a?(TaskRef) ? tr.to_workflow_task : tr }
            end
          end

          # Convert default_case from TaskRef array to WorkflowTask array
          return unless @options[:default_case] && !@options[:default_case].empty?

          wf_task.default_case = @options[:default_case].map do |tr|
            tr.is_a?(TaskRef) ? tr.to_workflow_task : tr
          end
        end

        def apply_fork_join_fields(wf_task)
          # Convert fork_branches from TaskRef arrays to WorkflowTask arrays
          return unless @options[:fork_branches]

          wf_task.fork_tasks = @options[:fork_branches].map do |branch|
            branch.map { |tr| tr.is_a?(TaskRef) ? tr.to_workflow_task : tr }
          end
        end

        def apply_join_fields(wf_task)
          wf_task.join_on = @options[:join_on]
          wf_task.expression = @options[:expression] if @options[:expression]
          wf_task.evaluator_type = @options[:evaluator_type] if @options[:evaluator_type]
        end

        def apply_do_while_fields(wf_task)
          wf_task.loop_condition = @options[:loop_condition]

          # Convert loop_over from TaskRef array to WorkflowTask array
          return unless @options[:loop_over]

          wf_task.loop_over = @options[:loop_over].map do |tr|
            tr.is_a?(TaskRef) ? tr.to_workflow_task : tr
          end
        end

        def apply_sub_workflow_fields(wf_task)
          # Handle inline workflow definition
          if @options[:inline_workflow_def]
            wf_task.sub_workflow_param = Conductor::Http::Models::SubWorkflowParams.new(
              name: @options[:inline_workflow_def].name,
              version: @options[:inline_workflow_def].version,
              workflow_definition: @options[:inline_workflow_def]
            )
          elsif @options[:sub_workflow_name]
            wf_task.sub_workflow_param = Conductor::Http::Models::SubWorkflowParams.new(
              name: @options[:sub_workflow_name],
              version: @options[:sub_workflow_version]
            )
          end
        end

        def apply_dynamic_fork_fields(wf_task)
          wf_task.dynamic_fork_join_tasks_param = @options[:dynamic_fork_tasks_param]
          wf_task.dynamic_fork_tasks_input_param_name = @options[:dynamic_fork_tasks_input_param]
        end
      end
    end
  end
end
