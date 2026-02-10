# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # Permission model - represents a permission entry
      class Permission < BaseModel
        SWAGGER_TYPES = {
          name: 'String'
        }.freeze

        ATTRIBUTE_MAP = {
          name: :name
        }.freeze

        attr_accessor :name

        def initialize(params = {})
          @name = params[:name]
        end
      end
    end
  end
end
