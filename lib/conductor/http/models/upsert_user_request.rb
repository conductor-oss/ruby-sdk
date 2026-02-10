# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # User role constants
      module UserRole
        ADMIN = 'ADMIN'
        USER = 'USER'
        WORKER = 'WORKER'
        METADATA_MANAGER = 'METADATA_MANAGER'
        WORKFLOW_MANAGER = 'WORKFLOW_MANAGER'
      end

      # UpsertUserRequest model - request to create or update a user
      class UpsertUserRequest < BaseModel
        SWAGGER_TYPES = {
          name: 'String',
          roles: 'Array<String>',
          groups: 'Array<String>'
        }.freeze

        ATTRIBUTE_MAP = {
          name: :name,
          roles: :roles,
          groups: :groups
        }.freeze

        attr_accessor :name, :roles, :groups

        def initialize(params = {})
          @name = params[:name]
          @roles = params[:roles]
          @groups = params[:groups]
        end
      end
    end
  end
end
