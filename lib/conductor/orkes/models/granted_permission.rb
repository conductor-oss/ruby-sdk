# frozen_string_literal: true

module Conductor
  module Orkes
    module Models
      # GrantedPermission model - represents a permission granted on a target
      class GrantedPermission < Conductor::Http::Models::BaseModel
        SWAGGER_TYPES = {
          target: 'TargetRef',
          access: 'Array<String>'
        }.freeze

        ATTRIBUTE_MAP = {
          target: :target,
          access: :access
        }.freeze

        attr_accessor :target, :access

        def initialize(params = {})
          @target = params[:target]
          @access = params[:access]
        end
      end
    end
  end
end
