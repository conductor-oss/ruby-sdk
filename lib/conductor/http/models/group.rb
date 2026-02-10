# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # Group model - represents a user group
      class Group < BaseModel
        SWAGGER_TYPES = {
          id: 'String',
          description: 'String',
          roles: 'Array<Role>',
          default_access: 'Hash<String, Array<String>>',
          contact_information: 'Hash<String, String>'
        }.freeze

        ATTRIBUTE_MAP = {
          id: :id,
          description: :description,
          roles: :roles,
          default_access: :defaultAccess,
          contact_information: :contactInformation
        }.freeze

        attr_accessor :id, :description, :roles, :default_access, :contact_information

        def initialize(params = {})
          @id = params[:id]
          @description = params[:description]
          @roles = params[:roles]
          @default_access = params[:default_access]
          @contact_information = params[:contact_information]
        end
      end
    end
  end
end
