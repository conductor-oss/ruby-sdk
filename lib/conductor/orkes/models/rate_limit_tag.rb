# frozen_string_literal: true

module Conductor
  module Orkes
    module Models
      # RateLimitTag - a tag with type RATE_LIMIT
      # Convenience subclass of TagObject that sets type to RATE_LIMIT
      class RateLimitTag < Conductor::Http::Models::TagObject
        def initialize(key:, value:)
          super(key: key, type: Conductor::Http::Models::TagType::RATE_LIMIT, value: value)
        end
      end
    end
  end
end
