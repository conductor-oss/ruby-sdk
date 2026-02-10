# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # UpsertGroupRequest model - request to create or update a group
      class UpsertGroupRequest < BaseModel
        SWAGGER_TYPES = {
          default_access: 'Hash<String, Array<String>>',
          description: 'String',
          roles: 'Array<String>'
        }.freeze

        ATTRIBUTE_MAP = {
          default_access: :defaultAccess,
          description: :description,
          roles: :roles
        }.freeze

        attr_accessor :default_access, :description, :roles

        def initialize(params = {})
          @default_access = params[:default_access]
          @description = params[:description]
          @roles = params[:roles]
        end
      end
    end
  end
end
