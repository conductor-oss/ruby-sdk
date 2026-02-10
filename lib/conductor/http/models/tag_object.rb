# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # Tag type constants
      module TagType
        METADATA = 'METADATA'
        RATE_LIMIT = 'RATE_LIMIT'
      end

      # TagObject model - base tag model for metadata and rate limit tags
      class TagObject < BaseModel
        SWAGGER_TYPES = {
          key: 'String',
          type: 'String',
          value: 'Object'
        }.freeze

        ATTRIBUTE_MAP = {
          key: :key,
          type: :type,
          value: :value
        }.freeze

        attr_accessor :key, :type, :value

        def initialize(params = {})
          @key = params[:key]
          @type = params[:type]
          @value = params[:value]
        end
      end
    end
  end
end
