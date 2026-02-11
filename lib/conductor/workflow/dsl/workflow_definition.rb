# frozen_string_literal: true

module Conductor
  module Workflow
    module Dsl
      # WorkflowDefinition wraps a WorkflowBuilder and provides methods
      # for registering and executing workflows.
      #
      # @example
      #   workflow = Conductor.workflow :my_workflow do
      #     simple :task1
      #   end
      #
      #   workflow.register(overwrite: true)
      #   result = workflow.execute(input: { foo: 'bar' })
      #
      class WorkflowDefinition
        attr_reader :builder

        # @param builder [WorkflowBuilder] The workflow builder
        # @param executor [WorkflowExecutor, nil] Optional workflow executor
        def initialize(builder, executor: nil)
          @builder = builder
          @executor = executor
        end

        # Get the workflow name
        # @return [String] Workflow name
        def name
          @builder.name
        end

        # Get the workflow version
        # @return [Integer, nil] Workflow version
        def version
          @builder.version
        end

        # Convert to WorkflowDef model
        # @return [Conductor::Http::Models::WorkflowDef] Workflow definition
        def to_workflow_def
          @builder.to_workflow_def
        end

        # Register this workflow with Conductor
        # @param overwrite [Boolean] Overwrite existing workflow definition (default: false)
        # @return [Object] API response
        # @raise [RuntimeError] If no executor is configured
        #
        # @example
        #   workflow.register(overwrite: true)
        def register(overwrite: false)
          raise 'Executor required for registration. Pass executor: option to Conductor.workflow' unless @executor

          @executor.register_workflow(self, overwrite: overwrite)
        end

        # Execute this workflow and wait for completion
        # @param input [Hash] Workflow input parameters (default: {})
        # @param wait_for_seconds [Integer] Maximum time to wait for completion (default: 30)
        # @param correlation_id [String, nil] Correlation ID for tracking
        # @param domain [String, nil] Task domain for all tasks
        # @param wait_until_task_ref [String, nil] Wait until specific task completes
        # @param request_id [String, nil] Unique request ID for idempotency
        # @return [WorkflowRun] Workflow execution result
        # @raise [RuntimeError] If no executor is configured
        #
        # @example
        #   result = workflow.execute(input: { user_id: 123 })
        #   puts result.status
        def execute(input: {}, wait_for_seconds: 30, correlation_id: nil, domain: nil,
                    wait_until_task_ref: nil, request_id: nil)
          raise 'Executor required for execution. Pass executor: option to Conductor.workflow' unless @executor

          @executor.execute(
            @builder.name,
            input: input,
            version: @builder.version,
            wait_for_seconds: wait_for_seconds,
            correlation_id: correlation_id,
            domain: domain,
            wait_until_task_ref: wait_until_task_ref,
            request_id: request_id
          )
        end

        # Execute this workflow (alias for execute)
        # @param input [Hash] Workflow input parameters
        # @return [WorkflowRun] Workflow execution result
        #
        # @example
        #   result = workflow.call(user_id: 123, email: 'user@example.com')
        def call(**input)
          execute(input: input)
        end

        # Start this workflow asynchronously (returns immediately with workflow ID)
        # @param input [Hash] Workflow input parameters (default: {})
        # @param correlation_id [String, nil] Correlation ID for tracking
        # @param domain [String, nil] Task domain for all tasks
        # @return [String] Workflow ID
        # @raise [RuntimeError] If no executor is configured
        #
        # @example
        #   workflow_id = workflow.start(input: { user_id: 123 })
        def start(input: {}, correlation_id: nil, domain: nil)
          raise 'Executor required for starting workflow. Pass executor: option to Conductor.workflow' unless @executor

          request = Conductor::Http::Models::StartWorkflowRequest.new(
            name: @builder.name,
            version: @builder.version,
            input: input,
            correlation_id: correlation_id
          )
          request.task_to_domain = { '*' => domain } if domain

          @executor.start_workflow(request)
        end

        # Get the workflow status
        # @param workflow_id [String] The workflow execution ID
        # @param include_tasks [Boolean] Include task details (default: true)
        # @return [Workflow] Workflow execution details
        # @raise [RuntimeError] If no executor is configured
        #
        # @example
        #   workflow_id = workflow.start(input: { user_id: 123 })
        #   status = workflow.status(workflow_id)
        def status(workflow_id, include_tasks: true)
          raise 'Executor required for checking status. Pass executor: option to Conductor.workflow' unless @executor

          @executor.get_workflow(workflow_id, include_tasks: include_tasks)
        end

        # Inspect the workflow definition
        # @return [String] Human-readable representation
        def inspect
          "#<Conductor::Workflow::Dsl::WorkflowDefinition name=#{@builder.name.inspect} " \
            "version=#{@builder.version.inspect} tasks=#{@builder.tasks.size}>"
        end

        # Convert to string
        # @return [String] Workflow name and version
        def to_s
          "#{@builder.name}:#{@builder.version || 'latest'}"
        end
      end
    end
  end
end
