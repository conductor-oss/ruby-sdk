# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # Task execution log entry
      class TaskExecLog < BaseModel
        SWAGGER_TYPES = {
          log: 'String',
          task_id: 'String',
          created_time: 'Integer'
        }.freeze

        ATTRIBUTE_MAP = {
          log: :log,
          task_id: :taskId,
          created_time: :createdTime
        }.freeze

        attr_accessor :log, :task_id, :created_time

        def initialize(params = {})
          @log = params[:log]
          @task_id = params[:task_id]
          @created_time = params[:created_time]
        end
      end
    end
  end
end
