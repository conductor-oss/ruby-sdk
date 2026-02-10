# frozen_string_literal: true

require_relative '../api_client'

module Conductor
  module Http
    module Api
      # PromptResourceApi - API for prompt template management operations (Orkes)
      class PromptResourceApi
        attr_accessor :api_client

        def initialize(api_client = nil)
          @api_client = api_client || ApiClient.new
        end

        # Save a prompt template
        # @param [String] name Prompt name
        # @param [String] body Prompt template text
        # @param [String] description Description
        # @param [Array<String>] models Associated models
        # @param [Integer] version Version number
        # @param [Boolean] auto_increment Auto increment version
        def save_prompt(name, body, description: nil, models: nil, version: nil, auto_increment: false)
          query = {}
          query[:description] = description if description
          query[:models] = models if models
          query[:version] = version if version
          query[:autoIncrement] = auto_increment if auto_increment

          @api_client.call_api(
            '/prompts/{name}',
            'POST',
            path_params: { name: name },
            query_params: query,
            body: body,
            return_http_data_only: true
          )
        end

        # Get a prompt template
        def get_prompt(name)
          @api_client.call_api('/prompts/{name}', 'GET', path_params: { name: name }, return_type: 'PromptTemplate',
                                                         return_http_data_only: true)
        end

        # Get all prompt templates
        def get_prompts
          @api_client.call_api('/prompts', 'GET', return_type: 'Array<PromptTemplate>', return_http_data_only: true)
        end

        # Delete a prompt template
        def delete_prompt(name)
          @api_client.call_api('/prompts/{name}', 'DELETE', path_params: { name: name }, return_http_data_only: true)
        end

        # Get tags for a prompt template
        def get_tags_for_prompt_template(name)
          @api_client.call_api('/prompts/{name}/tags', 'GET', path_params: { name: name },
                                                              return_type: 'Array<TagObject>', return_http_data_only: true)
        end

        # Update tags for a prompt template
        def update_tag_for_prompt_template(name, tags)
          @api_client.call_api('/prompts/{name}/tags', 'PUT', path_params: { name: name }, body: tags,
                                                              return_http_data_only: true)
        end

        # Delete tags for a prompt template
        def delete_tag_for_prompt_template(name, tags)
          @api_client.call_api('/prompts/{name}/tags', 'DELETE', path_params: { name: name }, body: tags,
                                                                 return_http_data_only: true)
        end

        # Test a prompt template
        def test_prompt(body)
          @api_client.call_api('/prompts/test', 'POST', body: body, return_type: 'String', return_http_data_only: true)
        end
      end
    end
  end
end
