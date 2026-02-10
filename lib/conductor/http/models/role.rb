# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # Role model - represents a role with permissions
      class Role < BaseModel
        SWAGGER_TYPES = {
          name: 'String',
          permissions: 'Array<Permission>'
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
