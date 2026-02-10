# frozen_string_literal: true

require_relative '../api_client'

module Conductor
  module Http
    module Api
      # RoleResourceApi - API for role management operations (Orkes)
      class RoleResourceApi
        attr_accessor :api_client

        def initialize(api_client = nil)
          @api_client = api_client || ApiClient.new
        end

        # List all roles
        def list_all_roles
          @api_client.call_api('/roles', 'GET', return_type: 'Array<Role>', return_http_data_only: true)
        end

        # List system roles
        def list_system_roles
          @api_client.call_api('/roles/system', 'GET', return_type: 'Object', return_http_data_only: true)
        end

        # List custom roles
        def list_custom_roles
          @api_client.call_api('/roles/custom', 'GET', return_type: 'Array<Role>', return_http_data_only: true)
        end

        # List available permissions
        def list_available_permissions
          @api_client.call_api('/roles/permissions', 'GET', return_type: 'Object', return_http_data_only: true)
        end

        # Create a role
        def create_role(body)
          @api_client.call_api('/roles', 'POST', body: body, return_type: 'Object', return_http_data_only: true)
        end

        # Get a role by name
        def get_role(name)
          @api_client.call_api('/roles/{name}', 'GET', path_params: { name: name }, return_type: 'Object',
                                                       return_http_data_only: true)
        end

        # Update a role
        def update_role(name, body)
          @api_client.call_api('/roles/{name}', 'PUT', path_params: { name: name }, body: body, return_type: 'Object',
                                                       return_http_data_only: true)
        end

        # Delete a role
        def delete_role(name)
          @api_client.call_api('/roles/{name}', 'DELETE', path_params: { name: name }, return_http_data_only: true)
        end
      end
    end
  end
end
