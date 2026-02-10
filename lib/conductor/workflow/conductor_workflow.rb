# frozen_string_literal: true

require 'securerandom'

module Conductor
  module Workflow
    # ConductorWorkflow is the main class for defining workflows using the DSL
    # It provides a fluent interface for building workflow definitions programmatically
    #
    # @example Basic workflow with chaining
    #   workflow = ConductorWorkflow.new(workflow_client, 'my_workflow')
    #     .timeout_seconds(3600)
    #     .description('My workflow description')
    #
    #   # Add tasks using >> operator
    #   workflow >> SimpleTask.new('task1', 'task1_ref')
    #   workflow >> SimpleTask.new('task2', 'task2_ref')
    #
    #   # Register and start
    #   workflow.register(overwrite: true)
    #   workflow_id = workflow.start_workflow_with_input(input: { key: 'value' })
    #
    # @example Parallel execution with arrays
    #   # Fork-join is automatic when passing arrays
    #   workflow >> [
    #     [task_a1, task_a2],  # Branch 1
    #     [task_b1]           # Branch 2
    #   ]
    #
    class ConductorWorkflow
      SCHEMA_VERSION = 2

      attr_accessor :name, :version
      attr_writer :description, :timeout_seconds, :owner_email
      attr_reader :tasks

      # Create a new ConductorWorkflow
      #
      # Supports two calling conventions:
      #   ConductorWorkflow.new(workflow_client, 'name')          # positional
      #   ConductorWorkflow.new(executor: executor, name: 'name') # keyword
      #
      # @param workflow_client [Conductor::Client::WorkflowClient, WorkflowExecutor, nil] Client for API calls
      # @param name [String, nil] The workflow name
      # @param version [Integer, nil] Optional workflow version
      # @param description [String, nil] Optional workflow description
      # @param executor [WorkflowExecutor, nil] Alternative to workflow_client
      def initialize(workflow_client = nil, name = nil, version: nil, description: nil, executor: nil)
        @workflow_client = workflow_client || executor
        @name = name
        @version = version
        @description = description
        @tasks = []
        @owner_email = nil
        @timeout_policy = nil
        @timeout_seconds = 60
        @failure_workflow = ''
        @input_parameters = []
        @output_parameters = {}
        @input_template = {}
        @variables = {}
        @restartable = true
        @workflow_status_listener_enabled = false
        @workflow_status_listener_sink = nil
      end

      # Set or get description (fluent interface when setting)
      # @param desc [String, nil] Description to set (nil to get current value)
      # @return [self, String] Returns self when setting, description when getting
      def description(desc = nil)
        if desc.nil?
          @description
        else
          @description = desc
          self
        end
      end

      # Set timeout policy (fluent interface)
      # @param policy [String] Timeout policy (TimeoutPolicy::TIME_OUT_WORKFLOW or ALERT_ONLY)
      # @return [self]
      def timeout_policy(policy)
        @timeout_policy = policy
        self
      end

      # Set timeout in seconds (fluent interface)
      # @param seconds [Integer] Timeout duration
      # @return [self]
      def timeout_seconds(seconds)
        @timeout_seconds = seconds
        self
      end

      # Set owner email (fluent interface)
      # @param email [String] Owner email address
      # @return [self]
      def owner_email(email)
        @owner_email = email
        self
      end

      # Set failure workflow (fluent interface)
      # @param workflow_name [String] Name of workflow to run on failure
      # @return [self]
      def failure_workflow(workflow_name)
        @failure_workflow = workflow_name
        self
      end

      # Set whether workflow is restartable (fluent interface)
      # @param value [Boolean] Whether workflow can be restarted
      # @return [self]
      def restartable(value)
        @restartable = value
        self
      end

      # Enable workflow status listener (fluent interface)
      # @param sink_name [String] The sink name for status events
      # @return [self]
      def enable_status_listener(sink_name)
        @workflow_status_listener_sink = sink_name
        @workflow_status_listener_enabled = true
        self
      end

      # Disable workflow status listener (fluent interface)
      # @return [self]
      def disable_status_listener
        @workflow_status_listener_sink = nil
        @workflow_status_listener_enabled = false
        self
      end

      # Set output parameters mapping (fluent interface)
      # @param params [Hash<String, Object>] Output parameter mapping
      # @return [self]
      def output_parameters(params)
        @output_parameters = params || {}
        self
      end

      # Set a single output parameter (fluent interface)
      # @param key [String] Output parameter name
      # @param value [Object] Output parameter value/expression
      # @return [self]
      def output_parameter(key, value)
        @output_parameters ||= {}
        @output_parameters[key] = value
        self
      end

      # Set input template (fluent interface)
      # @param template [Hash<String, Object>] Input template
      # @return [self]
      def input_template(template)
        @input_template = template || {}
        self
      end

      # Set input parameters (for documentation) (fluent interface)
      # @param params [Array<String>, Hash] Input parameters or template
      # @return [self]
      def input_parameters(params)
        if params.is_a?(Hash)
          @input_template = params
        else
          @input_parameters = params || []
        end
        self
      end

      # Set workflow variables (fluent interface)
      # @param vars [Hash<String, Object>] Variables
      # @return [self]
      def variables(vars)
        @variables = vars || {}
        self
      end

      # Alias for input_template
      # @param input [Hash] Workflow input template
      # @return [self]
      def workflow_input(input)
        input_template(input)
      end

      # Add task(s) using >> operator
      # This is the primary way to build workflow task chains
      # @param task [TaskInterface, Array, ConductorWorkflow] Task(s) to add
      # @return [self]
      # @example Sequential tasks
      #   workflow >> task1 >> task2 >> task3
      # @example Parallel execution (fork-join)
      #   workflow >> [[branch1_task1, branch1_task2], [branch2_task1]]
      def >>(task)
        case task
        when Array
          # Fork-join: array of arrays of tasks
          forked_tasks = task.map do |fork_task|
            fork_task.is_a?(Array) ? fork_task : [fork_task]
          end
          add_fork_join_tasks(forked_tasks)
        when ConductorWorkflow
          # Inline sub-workflow
          inline = InlineSubWorkflowTask.new(
            "#{task.name}_#{SecureRandom.uuid[0..7]}",
            task
          )
          inline.input_parameters.merge!(task.instance_variable_get(:@input_template))
          add_task(inline)
        else
          add_task(task)
        end
        self
      end

      # Add task(s) to the workflow
      # @param task [TaskInterface, Array<TaskInterface>] Task(s) to add
      # @return [self]
      def add(task)
        if task.is_a?(Array)
          task.each { |t| add_task(t) }
        else
          add_task(task)
        end
        self
      end

      # Register the workflow definition with Conductor server
      # @param overwrite [Boolean] Whether to overwrite existing definition
      # @return [Object] API response
      def register(overwrite: false)
        workflow_def = to_workflow_def
        @workflow_client.register_workflow(workflow_def, overwrite: overwrite)
      end

      # Start the workflow with given input
      # @param input [Hash] Workflow input data
      # @param correlation_id [String, nil] Optional correlation ID
      # @param task_to_domain [Hash<String, String>, nil] Task to domain mapping
      # @param priority [Integer, nil] Workflow priority
      # @param idempotency_key [String, nil] Idempotency key
      # @return [String] Workflow execution ID
      def start_workflow_with_input(input: {}, correlation_id: nil, task_to_domain: nil,
                                    priority: nil, idempotency_key: nil)
        request = Conductor::Http::Models::StartWorkflowRequest.new(
          name: @name,
          version: @version,
          input: input,
          correlation_id: correlation_id,
          task_to_domain: task_to_domain,
          priority: priority,
          idempotency_key: idempotency_key,
          workflow_def: to_workflow_def
        )
        @workflow_client.start_workflow(request)
      end

      # Start workflow with a StartWorkflowRequest
      # @param request [Conductor::Http::Models::StartWorkflowRequest] The request
      # @return [String] Workflow execution ID
      def start_workflow(request)
        request.workflow_def = to_workflow_def
        request.name = @name
        request.version = @version
        @workflow_client.start_workflow(request)
      end

      # Convert to WorkflowDef for serialization/registration
      # @return [Conductor::Http::Models::WorkflowDef]
      def to_workflow_def
        Conductor::Http::Models::WorkflowDef.new(
          name: @name,
          description: @description,
          version: @version,
          tasks: get_workflow_task_list,
          input_parameters: @input_parameters,
          output_parameters: @output_parameters,
          failure_workflow: @failure_workflow,
          schema_version: SCHEMA_VERSION,
          owner_email: @owner_email,
          timeout_policy: @timeout_policy,
          timeout_seconds: @timeout_seconds,
          variables: @variables,
          input_template: @input_template,
          workflow_status_listener_enabled: @workflow_status_listener_enabled,
          workflow_status_listener_sink: @workflow_status_listener_sink,
          restartable: @restartable
        )
      end

      # Convert workflow to a sub-workflow task (for embedding in other workflows)
      # @return [Conductor::Http::Models::WorkflowTask]
      def to_workflow_task
        inline = InlineSubWorkflowTask.new("#{@name}_#{SecureRandom.uuid[0..7]}", self)
        inline.input_parameters.merge!(@input_template)
        inline.to_workflow_task
      end

      # Get reference to workflow input
      # @param json_path [String, nil] Optional JSON path
      # @return [String] Expression string
      def input(json_path = nil)
        if json_path.nil?
          '${workflow.input}'
        else
          "${workflow.input.#{json_path}}"
        end
      end

      # Get reference to workflow output
      # @param json_path [String, nil] Optional JSON path
      # @return [String] Expression string
      def output(json_path = nil)
        if json_path.nil?
          '${workflow.output}'
        else
          "${workflow.output.#{json_path}}"
        end
      end

      private

      def add_task(task)
        unless task.is_a?(TaskInterface) || task.is_a?(ConductorWorkflow)
          raise ArgumentError, "Invalid task type: #{task.class}. Expected TaskInterface or ConductorWorkflow"
        end

        @tasks << task.dup
        self
      end

      def add_fork_join_tasks(forked_tasks)
        forked_tasks.each do |branch|
          branch.each do |task|
            unless task.is_a?(TaskInterface) || task.is_a?(ConductorWorkflow)
              raise ArgumentError, "Invalid task type in fork: #{task.class}"
            end
          end
        end

        suffix = SecureRandom.uuid[0..7]
        fork_task = ForkTask.new("forked_#{suffix}", forked_tasks)
        @tasks << fork_task
        self
      end

      def get_workflow_task_list
        workflow_task_list = []

        @tasks.each do |task|
          converted = task.to_workflow_task
          if converted.is_a?(Array)
            workflow_task_list.concat(converted)
          else
            workflow_task_list << converted
          end
        end

        # Auto-insert JOIN tasks after FORK_JOIN if not already present
        updated_list = []
        workflow_task_list.each_with_index do |wf_task, i|
          updated_list << wf_task

          if wf_task.type == TaskType::FORK_JOIN
            next_task = workflow_task_list[i + 1]
            # If next task is not a JOIN, auto-generate one
            if next_task.nil? || next_task.type != TaskType::JOIN
              join_on = wf_task.fork_tasks.map { |branch| branch.last.task_reference_name }
              join = JoinTask.new("join_#{wf_task.task_reference_name}", join_on: join_on)
              updated_list << join.to_workflow_task
            end
          end
        end

        updated_list
      end
    end
  end
end
