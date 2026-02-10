# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # Event handler definition
      class EventHandler < BaseModel
        SWAGGER_TYPES = {
          name: 'String',
          event: 'String',
          condition: 'String',
          actions: 'Array<EventHandlerAction>',
          active: 'Boolean',
          evaluator_type: 'String'
        }.freeze

        ATTRIBUTE_MAP = {
          name: :name,
          event: :event,
          condition: :condition,
          actions: :actions,
          active: :active,
          evaluator_type: :evaluatorType
        }.freeze

        attr_accessor :name, :event, :condition, :actions, :active, :evaluator_type

        def initialize(params = {})
          @name = params[:name]
          @event = params[:event]
          @condition = params[:condition]
          @actions = params[:actions] || []
          @active = params.fetch(:active, true)
          @evaluator_type = params[:evaluator_type]
        end
      end

      # Action within an event handler
      class EventHandlerAction < BaseModel
        SWAGGER_TYPES = {
          action: 'String',
          start_workflow: 'StartWorkflow',
          complete_task: 'TaskDetails',
          fail_task: 'TaskDetails',
          expand_inline_json: 'Boolean'
        }.freeze

        ATTRIBUTE_MAP = {
          action: :action,
          start_workflow: :start_workflow,
          complete_task: :complete_task,
          fail_task: :fail_task,
          expand_inline_json: :expandInlineJSON
        }.freeze

        # Action types
        module ActionType
          START_WORKFLOW = 'start_workflow'
          COMPLETE_TASK = 'complete_task'
          FAIL_TASK = 'fail_task'
        end

        attr_accessor :action, :start_workflow, :complete_task, :fail_task, :expand_inline_json

        def initialize(params = {})
          @action = params[:action]
          @start_workflow = params[:start_workflow]
          @complete_task = params[:complete_task]
          @fail_task = params[:fail_task]
          @expand_inline_json = params.fetch(:expand_inline_json, false)
        end
      end

      # Start workflow action details
      class StartWorkflow < BaseModel
        SWAGGER_TYPES = {
          name: 'String',
          version: 'Integer',
          input: 'Hash<String, Object>',
          correlation_id: 'String',
          task_to_domain: 'Hash<String, String>'
        }.freeze

        ATTRIBUTE_MAP = {
          name: :name,
          version: :version,
          input: :input,
          correlation_id: :correlationId,
          task_to_domain: :taskToDomain
        }.freeze

        attr_accessor :name, :version, :input, :correlation_id, :task_to_domain

        def initialize(params = {})
          @name = params[:name]
          @version = params[:version]
          @input = params[:input] || {}
          @correlation_id = params[:correlation_id]
          @task_to_domain = params[:task_to_domain]
        end
      end

      # Task details for event handler actions (complete_task / fail_task)
      class TaskDetails < BaseModel
        SWAGGER_TYPES = {
          workflow_id: 'String',
          task_ref_name: 'String',
          output: 'Hash<String, Object>',
          task_id: 'String'
        }.freeze

        ATTRIBUTE_MAP = {
          workflow_id: :workflowId,
          task_ref_name: :taskRefName,
          output: :output,
          task_id: :taskId
        }.freeze

        attr_accessor :workflow_id, :task_ref_name, :output, :task_id

        def initialize(params = {})
          @workflow_id = params[:workflow_id]
          @task_ref_name = params[:task_ref_name]
          @output = params[:output] || {}
          @task_id = params[:task_id]
        end
      end
    end
  end
end
