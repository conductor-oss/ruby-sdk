# frozen_string_literal: true

require_relative '../api_client'

module Conductor
  module Http
    module Api
      # ApplicationResourceApi - API for application management operations (Orkes)
      class ApplicationResourceApi
        attr_accessor :api_client

        def initialize(api_client = nil)
          @api_client = api_client || ApiClient.new
        end

        # Create an application
        def create_application(body)
          @api_client.call_api('/applications', 'POST', body: body, return_type: 'ConductorApplication', return_http_data_only: true)
        end

        # Get an application by ID
        def get_application(id)
          @api_client.call_api('/applications/{id}', 'GET', path_params: { id: id }, return_type: 'ConductorApplication', return_http_data_only: true)
        end

        # List all applications
        def list_applications
          @api_client.call_api('/applications', 'GET', return_type: 'Array<ConductorApplication>', return_http_data_only: true)
        end

        # Update an application
        def update_application(body, id)
          @api_client.call_api('/applications/{id}', 'PUT', path_params: { id: id }, body: body, return_type: 'ConductorApplication', return_http_data_only: true)
        end

        # Delete an application
        def delete_application(id)
          @api_client.call_api('/applications/{id}', 'DELETE', path_params: { id: id }, return_http_data_only: true)
        end

        # Add a role to an application
        def add_role_to_application_user(application_id, role)
          @api_client.call_api('/applications/{applicationId}/roles/{role}', 'POST', path_params: { applicationId: application_id, role: role }, return_http_data_only: true)
        end

        # Remove a role from an application
        def remove_role_from_application_user(application_id, role)
          @api_client.call_api('/applications/{applicationId}/roles/{role}', 'DELETE', path_params: { applicationId: application_id, role: role }, return_http_data_only: true)
        end

        # Set tags for an application
        def put_tags_for_application(tags, id)
          @api_client.call_api('/applications/{id}/tags', 'PUT', path_params: { id: id }, body: tags, return_http_data_only: true)
        end

        # Get tags for an application
        def get_tags_for_application(id)
          @api_client.call_api('/applications/{id}/tags', 'GET', path_params: { id: id }, return_type: 'Array<TagObject>', return_http_data_only: true)
        end

        # Delete tags for an application
        def delete_tags_for_application(tags, id)
          @api_client.call_api('/applications/{id}/tags', 'DELETE', path_params: { id: id }, body: tags, return_http_data_only: true)
        end

        # Create an access key for an application
        def create_access_key(id)
          @api_client.call_api('/applications/{id}/accessKeys', 'POST', path_params: { id: id }, return_type: 'Object', return_http_data_only: true)
        end

        # Get access keys for an application
        def get_access_keys(id)
          @api_client.call_api('/applications/{id}/accessKeys', 'GET', path_params: { id: id }, return_type: 'Array<Object>', return_http_data_only: true)
        end

        # Toggle access key status
        def toggle_access_key_status(application_id, key_id)
          @api_client.call_api('/applications/{applicationId}/accessKeys/{keyId}/status', 'POST', path_params: { applicationId: application_id, keyId: key_id }, return_type: 'Object', return_http_data_only: true)
        end

        # Delete an access key
        def delete_access_key(application_id, key_id)
          @api_client.call_api('/applications/{applicationId}/accessKeys/{keyId}', 'DELETE', path_params: { applicationId: application_id, keyId: key_id }, return_http_data_only: true)
        end

        # Get application by access key ID
        def get_app_by_access_key_id(access_key_id)
          @api_client.call_api('/applications/key/{accessKeyId}', 'GET', path_params: { accessKeyId: access_key_id }, return_type: 'Object', return_http_data_only: true)
        end
      end
    end
  end
end
