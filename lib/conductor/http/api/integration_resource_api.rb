# frozen_string_literal: true

require_relative '../api_client'

module Conductor
  module Http
    module Api
      # IntegrationResourceApi - API for integration management operations (Orkes)
      class IntegrationResourceApi
        attr_accessor :api_client

        def initialize(api_client = nil)
          @api_client = api_client || ApiClient.new
        end

        # Save (create/update) an integration provider
        def save_integration(body, name)
          @api_client.call_api('/integrations/provider/{name}', 'POST', path_params: { name: name }, body: body,
                                                                        return_http_data_only: true)
        end

        # Get an integration provider
        def get_integration(name)
          @api_client.call_api('/integrations/provider/{name}', 'GET', path_params: { name: name },
                                                                       return_type: 'Integration', return_http_data_only: true)
        end

        # Get all integration providers
        def get_integrations
          @api_client.call_api('/integrations/provider', 'GET', return_type: 'Array<Integration>',
                                                                return_http_data_only: true)
        end

        # Delete an integration provider
        def delete_integration(name)
          @api_client.call_api('/integrations/provider/{name}', 'DELETE', path_params: { name: name },
                                                                          return_http_data_only: true)
        end

        # Save (create/update) an integration API
        def save_integration_api(body, name, integration_name)
          @api_client.call_api('/integrations/provider/{name}/integration/{integration_name}', 'POST',
                               path_params: { name: name, integration_name: integration_name }, body: body, return_http_data_only: true)
        end

        # Get an integration API
        def get_integration_api(name, integration_name)
          @api_client.call_api('/integrations/provider/{name}/integration/{integration_name}', 'GET',
                               path_params: { name: name, integration_name: integration_name }, return_type: 'IntegrationApi', return_http_data_only: true)
        end

        # Get all integration APIs for a provider
        def get_integration_apis(name)
          @api_client.call_api('/integrations/provider/{name}/integration', 'GET',
                               path_params: { name: name }, return_type: 'Array<IntegrationApi>', return_http_data_only: true)
        end

        # Delete an integration API
        def delete_integration_api(name, integration_name)
          @api_client.call_api('/integrations/provider/{name}/integration/{integration_name}', 'DELETE',
                               path_params: { name: name, integration_name: integration_name }, return_http_data_only: true)
        end

        # Associate a prompt with an integration
        def associate_prompt_with_integration(integration_provider, integration_name, prompt_name)
          @api_client.call_api('/integrations/provider/{integration_provider}/integration/{integration_name}/prompt/{prompt_name}', 'POST',
                               path_params: { integration_provider: integration_provider, integration_name: integration_name, prompt_name: prompt_name },
                               return_http_data_only: true)
        end

        # Get prompts associated with an integration
        def get_prompts_with_integration(integration_provider, integration_name)
          @api_client.call_api('/integrations/provider/{integration_provider}/integration/{integration_name}/prompt', 'GET',
                               path_params: { integration_provider: integration_provider, integration_name: integration_name },
                               return_type: 'Array<PromptTemplate>', return_http_data_only: true)
        end

        # Get token usage for an integration API
        def get_token_usage_for_integration(name, integration_name)
          @api_client.call_api('/integrations/provider/{name}/integration/{integration_name}/metrics', 'GET',
                               path_params: { name: name, integration_name: integration_name }, return_type: 'Integer', return_http_data_only: true)
        end

        # Get token usage for an integration provider
        def get_token_usage_for_integration_provider(name)
          @api_client.call_api('/integrations/provider/{name}/metrics', 'GET',
                               path_params: { name: name }, return_type: 'Object', return_http_data_only: true)
        end

        # Set tags for an integration API
        def put_tag_for_integration(body, name, integration_name)
          @api_client.call_api('/integrations/provider/{name}/integration/{integration_name}/tags', 'PUT',
                               path_params: { name: name, integration_name: integration_name }, body: body, return_http_data_only: true)
        end

        # Get tags for an integration API
        def get_tags_for_integration(name, integration_name)
          @api_client.call_api('/integrations/provider/{name}/integration/{integration_name}/tags', 'GET',
                               path_params: { name: name, integration_name: integration_name }, return_type: 'Array<TagObject>', return_http_data_only: true)
        end

        # Delete tags for an integration API
        def delete_tag_for_integration(body, name, integration_name)
          @api_client.call_api('/integrations/provider/{name}/integration/{integration_name}/tags', 'DELETE',
                               path_params: { name: name, integration_name: integration_name }, body: body, return_http_data_only: true)
        end

        # Set tags for an integration provider
        def put_tag_for_integration_provider(body, name)
          @api_client.call_api('/integrations/provider/{name}/tags', 'PUT',
                               path_params: { name: name }, body: body, return_http_data_only: true)
        end

        # Get tags for an integration provider
        def get_tags_for_integration_provider(name)
          @api_client.call_api('/integrations/provider/{name}/tags', 'GET',
                               path_params: { name: name }, return_type: 'Array<TagObject>', return_http_data_only: true)
        end

        # Delete tags for an integration provider
        def delete_tag_for_integration_provider(body, name)
          @api_client.call_api('/integrations/provider/{name}/tags', 'DELETE',
                               path_params: { name: name }, body: body, return_http_data_only: true)
        end

        # Get available APIs for an integration
        def get_integration_available_apis(name)
          @api_client.call_api('/integrations/provider/{name}/integration/all', 'GET',
                               path_params: { name: name }, return_type: 'Array<IntegrationApi>', return_http_data_only: true)
        end

        # Get integration provider definitions
        def get_integration_provider_defs
          @api_client.call_api('/integrations/def', 'GET', return_type: 'Object', return_http_data_only: true)
        end

        # Get all providers and integrations
        def get_providers_and_integrations
          @api_client.call_api('/integrations/all', 'GET', return_type: 'Array<Integration>',
                                                           return_http_data_only: true)
        end
      end
    end
  end
end
