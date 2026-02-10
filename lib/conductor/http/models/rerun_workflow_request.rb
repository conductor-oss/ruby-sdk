# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # Request to rerun a workflow from a specific task
      class RerunWorkflowRequest < BaseModel
        SWAGGER_TYPES = {
          re_run_from_workflow_id: 'String',
          workflow_input: 'Hash<String, Object>',
          re_run_from_task_id: 'String',
          task_input: 'Hash<String, Object>',
          correlation_id: 'String'
        }.freeze

        ATTRIBUTE_MAP = {
          re_run_from_workflow_id: :reRunFromWorkflowId,
          workflow_input: :workflowInput,
          re_run_from_task_id: :reRunFromTaskId,
          task_input: :taskInput,
          correlation_id: :correlationId
        }.freeze

        attr_accessor :re_run_from_workflow_id, :workflow_input, :re_run_from_task_id,
                      :task_input, :correlation_id

        def initialize(params = {})
          @re_run_from_workflow_id = params[:re_run_from_workflow_id]
          @workflow_input = params[:workflow_input]
          @re_run_from_task_id = params[:re_run_from_task_id]
          @task_input = params[:task_input]
          @correlation_id = params[:correlation_id]
        end
      end
    end
  end
end
