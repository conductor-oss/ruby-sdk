# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # Request to update workflow state (variables and/or task state)
      class WorkflowStateUpdate < BaseModel
        SWAGGER_TYPES = {
          task_reference_name: 'String',
          task_result: 'TaskResult',
          variables: 'Hash<String, Object>'
        }.freeze

        ATTRIBUTE_MAP = {
          task_reference_name: :taskReferenceName,
          task_result: :taskResult,
          variables: :variables
        }.freeze

        attr_accessor :task_reference_name, :task_result, :variables

        def initialize(params = {})
          @task_reference_name = params[:task_reference_name]
          @task_result = params[:task_result]
          @variables = params[:variables] || {}
        end
      end
    end
  end
end
