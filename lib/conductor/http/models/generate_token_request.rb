# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # GenerateTokenRequest model - request to generate an authentication token
      class GenerateTokenRequest < BaseModel
        SWAGGER_TYPES = {
          key_id: 'String',
          key_secret: 'String'
        }.freeze

        ATTRIBUTE_MAP = {
          key_id: :keyId,
          key_secret: :keySecret
        }.freeze

        attr_accessor :key_id, :key_secret

        def initialize(params = {})
          @key_id = params[:key_id]
          @key_secret = params[:key_secret]
        end
      end
    end
  end
end
