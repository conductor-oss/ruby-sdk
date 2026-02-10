# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # CreateOrUpdateApplicationRequest model - request to create or update an application
      class CreateOrUpdateApplicationRequest < BaseModel
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
