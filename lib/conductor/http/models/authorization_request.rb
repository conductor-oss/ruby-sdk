# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # Access type constants for authorization
      module AccessType
        CREATE = 'CREATE'
        READ = 'READ'
        UPDATE = 'UPDATE'
        DELETE = 'DELETE'
        EXECUTE = 'EXECUTE'
      end

      # AuthorizationRequest model - request to grant or revoke permissions
      class AuthorizationRequest < BaseModel
        SWAGGER_TYPES = {
          subject: 'SubjectRef',
          target: 'TargetRef',
          access: 'Array<String>'
        }.freeze

        ATTRIBUTE_MAP = {
          subject: :subject,
          target: :target,
          access: :access
        }.freeze

        attr_accessor :subject, :target, :access

        def initialize(params = {})
          @subject = params[:subject]
          @target = params[:target]
          @access = params[:access]
        end
      end
    end
  end
end
