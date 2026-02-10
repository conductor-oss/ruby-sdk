# frozen_string_literal: true

require_relative '../api_client'

module Conductor
  module Http
    module Api
      # GatewayAuthResourceApi - API for gateway authentication config (Orkes)
      class GatewayAuthResourceApi
        attr_accessor :api_client

        def initialize(api_client = nil)
          @api_client = api_client || ApiClient.new
        end

        # Create gateway auth config
        def create_config(body)
          @api_client.call_api('/gateway/config/auth', 'POST', body: body, return_type: 'String',
                                                               return_http_data_only: true)
        end

        # Get gateway auth config by ID
        def get_config(id)
          @api_client.call_api('/gateway/config/auth/{id}', 'GET', path_params: { id: id },
                                                                   return_type: 'AuthenticationConfig', return_http_data_only: true)
        end

        # List all gateway auth configs
        def list_configs
          @api_client.call_api('/gateway/config/auth', 'GET', return_type: 'Array<AuthenticationConfig>',
                                                              return_http_data_only: true)
        end

        # Update gateway auth config
        def update_config(id, body)
          @api_client.call_api('/gateway/config/auth/{id}', 'PUT', path_params: { id: id }, body: body,
                                                                   return_http_data_only: true)
        end

        # Delete gateway auth config
        def delete_config(id)
          @api_client.call_api('/gateway/config/auth/{id}', 'DELETE', path_params: { id: id },
                                                                      return_http_data_only: true)
        end
      end
    end
  end
end
