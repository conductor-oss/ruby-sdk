# frozen_string_literal: true

require_relative 'base_model'

module Conductor
  module Http
    module Models
      # Token model representing the authentication token response from Conductor server
      class Token < BaseModel
        SWAGGER_TYPES = {
          token: 'String',
          user_id: 'String'
        }.freeze

        ATTRIBUTE_MAP = {
          token: :token,
          user_id: :userId
        }.freeze

        attr_accessor :token, :user_id

        # Initialize a new Token
        # @param [Hash] attributes Model attributes in the form of hash
        def initialize(attributes = {})
          return unless attributes.is_a?(Hash)

          self.token = attributes[:token] if attributes.key?(:token)
          self.user_id = attributes[:user_id] if attributes.key?(:user_id)
        end
      end
    end
  end
end
