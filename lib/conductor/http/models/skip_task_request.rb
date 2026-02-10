# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # Request to skip a task in a running workflow
      class SkipTaskRequest < BaseModel
        SWAGGER_TYPES = {
          task_input: 'Hash<String, Object>',
          task_output: 'Hash<String, Object>'
        }.freeze

        ATTRIBUTE_MAP = {
          task_input: :taskInput,
          task_output: :taskOutput
        }.freeze

        attr_accessor :task_input, :task_output

        def initialize(params = {})
          @task_input = params[:task_input]
          @task_output = params[:task_output]
        end
      end
    end
  end
end
