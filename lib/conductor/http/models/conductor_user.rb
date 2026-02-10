# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # ConductorUser model - represents a user in Conductor
      class ConductorUser < BaseModel
        SWAGGER_TYPES = {
          id: 'String',
          name: 'String',
          roles: 'Array<Role>',
          groups: 'Array<Group>',
          uuid: 'String',
          application_user: 'Boolean',
          encrypted_id: 'Boolean',
          encrypted_id_display_value: 'String',
          contact_information: 'Hash<String, String>',
          namespace: 'String'
        }.freeze

        ATTRIBUTE_MAP = {
          id: :id,
          name: :name,
          roles: :roles,
          groups: :groups,
          uuid: :uuid,
          application_user: :applicationUser,
          encrypted_id: :encryptedId,
          encrypted_id_display_value: :encryptedIdDisplayValue,
          contact_information: :contactInformation,
          namespace: :namespace
        }.freeze

        attr_accessor :id, :name, :roles, :groups, :uuid, :application_user,
                      :encrypted_id, :encrypted_id_display_value,
                      :contact_information, :namespace

        def initialize(params = {})
          @id = params[:id]
          @name = params[:name]
          @roles = params[:roles]
          @groups = params[:groups]
          @uuid = params[:uuid]
          @application_user = params[:application_user]
          @encrypted_id = params[:encrypted_id]
          @encrypted_id_display_value = params[:encrypted_id_display_value]
          @contact_information = params[:contact_information]
          @namespace = params[:namespace]
        end
      end
    end
  end
end
