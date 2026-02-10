# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # Target type constants for authorization
      module TargetType
        WORKFLOW_DEF = 'WORKFLOW_DEF'
        TASK_DEF = 'TASK_DEF'
        APPLICATION = 'APPLICATION'
        USER = 'USER'
        SECRET = 'SECRET'
        SECRET_NAME = 'SECRET_NAME'
        TAG = 'TAG'
        DOMAIN = 'DOMAIN'
      end

      # TargetRef model - identifies a resource target for authorization
      class TargetRef < BaseModel
        SWAGGER_TYPES = {
          type: 'String',
          id: 'String'
        }.freeze

        ATTRIBUTE_MAP = {
          type: :type,
          id: :id
        }.freeze

        attr_accessor :type, :id

        def initialize(params = {})
          @type = params[:type]
          @id = params[:id]
        end
      end
    end
  end
end
