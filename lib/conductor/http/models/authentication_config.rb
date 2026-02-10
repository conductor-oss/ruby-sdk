# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # Authentication type constants
      module AuthenticationType
        NONE = 'NONE'
        API_KEY = 'API_KEY'
        OIDC = 'OIDC'
      end

      # AuthenticationConfig model - gateway authentication configuration
      class AuthenticationConfig < BaseModel
        SWAGGER_TYPES = {
          id: 'String',
          application_id: 'String',
          authentication_type: 'String',
          api_keys: 'Array<String>',
          audience: 'String',
          conductor_token: 'String',
          created_by: 'String',
          fallback_to_default_auth: 'Boolean',
          issuer_uri: 'String',
          passthrough: 'Boolean',
          token_in_workflow_input: 'Boolean',
          updated_by: 'String'
        }.freeze

        ATTRIBUTE_MAP = {
          id: :id,
          application_id: :applicationId,
          authentication_type: :authenticationType,
          api_keys: :apiKeys,
          audience: :audience,
          conductor_token: :conductorToken,
          created_by: :createdBy,
          fallback_to_default_auth: :fallbackToDefaultAuth,
          issuer_uri: :issuerUri,
          passthrough: :passthrough,
          token_in_workflow_input: :tokenInWorkflowInput,
          updated_by: :updatedBy
        }.freeze

        attr_accessor :id, :application_id, :authentication_type, :api_keys,
                      :audience, :conductor_token, :created_by,
                      :fallback_to_default_auth, :issuer_uri, :passthrough,
                      :token_in_workflow_input, :updated_by

        def initialize(params = {})
          @id = params[:id]
          @application_id = params[:application_id]
          @authentication_type = params[:authentication_type]
          @api_keys = params[:api_keys]
          @audience = params[:audience]
          @conductor_token = params[:conductor_token]
          @created_by = params[:created_by]
          @fallback_to_default_auth = params[:fallback_to_default_auth]
          @issuer_uri = params[:issuer_uri]
          @passthrough = params[:passthrough]
          @token_in_workflow_input = params[:token_in_workflow_input]
          @updated_by = params[:updated_by]
        end
      end
    end
  end
end
