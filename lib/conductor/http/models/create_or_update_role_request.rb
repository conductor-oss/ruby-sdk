# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # CreateOrUpdateRoleRequest model - request to create or update a role
      class CreateOrUpdateRoleRequest < BaseModel
        SWAGGER_TYPES = {
          name: 'String',
          permissions: 'Array<String>'
        }.freeze

        ATTRIBUTE_MAP = {
          name: :name,
          permissions: :permissions
        }.freeze

        attr_accessor :name, :permissions

        def initialize(params = {})
          @name = params[:name]
          @permissions = params[:permissions]
        end
      end
    end
  end
end
