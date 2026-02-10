# frozen_string_literal: true

require_relative '../api_client'

module Conductor
  module Http
    module Api
      # AuthorizationResourceApi - API for permission management operations (Orkes)
      class AuthorizationResourceApi
        attr_accessor :api_client

        def initialize(api_client = nil)
          @api_client = api_client || ApiClient.new
        end

        # Grant permissions
        # @param [AuthorizationRequest] body Authorization request
        # @return [void]
        def grant_permissions(body)
          @api_client.call_api(
            '/auth/authorization',
            'POST',
            body: body,
            return_http_data_only: true
          )
        end

        # Get permissions for a target
        # @param [String] type Target type
        # @param [String] id Target ID
        # @return [Hash]
        def get_permissions(type, id)
          @api_client.call_api(
            '/auth/authorization/{type}/{id}',
            'GET',
            path_params: { type: type, id: id },
            return_type: 'Object',
            return_http_data_only: true
          )
        end

        # Remove permissions
        # @param [AuthorizationRequest] body Authorization request
        # @return [void]
        def remove_permissions(body)
          @api_client.call_api(
            '/auth/authorization',
            'DELETE',
            body: body,
            return_http_data_only: true
          )
        end
      end
    end
  end
end
