# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # Subject type constants for authorization
      module SubjectType
        USER = 'USER'
        ROLE = 'ROLE'
        GROUP = 'GROUP'
        TAG = 'TAG'
      end

      # SubjectRef model - identifies a user, role, or group for authorization
      class SubjectRef < BaseModel
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
