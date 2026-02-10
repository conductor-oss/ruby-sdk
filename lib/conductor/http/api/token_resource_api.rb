# frozen_string_literal: true

require_relative '../api_client'

module Conductor
  module Http
    module Api
      # TokenResourceApi - API for token management operations (Orkes)
      class TokenResourceApi
        attr_accessor :api_client

        def initialize(api_client = nil)
          @api_client = api_client || ApiClient.new
        end

        # Generate a token
        # @param [GenerateTokenRequest] body Token request
        # @return [Hash]
        def generate_token(body)
          @api_client.call_api(
            '/token',
            'POST',
            body: body,
            return_type: 'Object',
            return_http_data_only: true
          )
        end

        # Get user info from current token
        # @return [Hash]
        def get_user_info
          @api_client.call_api(
            '/token/userInfo',
            'GET',
            return_type: 'Object',
            return_http_data_only: true
          )
        end
      end
    end
  end
end
