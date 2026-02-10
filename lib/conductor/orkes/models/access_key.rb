# frozen_string_literal: true

module Conductor
  module Orkes
    module Models
      # AccessKeyStatus constants
      module AccessKeyStatus
        ACTIVE = 'ACTIVE'
        INACTIVE = 'INACTIVE'
      end

      # AccessKey model - represents an application access key
      class AccessKey < Conductor::Http::Models::BaseModel
        SWAGGER_TYPES = {
          id: 'String',
          status: 'String',
          created_at: 'Integer'
        }.freeze

        ATTRIBUTE_MAP = {
          id: :id,
          status: :status,
          created_at: :createdAt
        }.freeze

        attr_accessor :id, :status, :created_at

        def initialize(params = {})
          @id = params[:id]
          @status = params[:status] || AccessKeyStatus::ACTIVE
          @created_at = params[:created_at]
        end
      end

      # CreatedAccessKey model - returned when creating a new access key
      class CreatedAccessKey < Conductor::Http::Models::BaseModel
        SWAGGER_TYPES = {
          id: 'String',
          secret: 'String'
        }.freeze

        ATTRIBUTE_MAP = {
          id: :id,
          secret: :secret
        }.freeze

        attr_accessor :id, :secret

        def initialize(params = {})
          @id = params[:id]
          @secret = params[:secret]
        end
      end
    end
  end
end
