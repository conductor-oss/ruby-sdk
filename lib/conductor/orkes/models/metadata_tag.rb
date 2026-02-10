# frozen_string_literal: true

module Conductor
  module Orkes
    module Models
      # MetadataTag - a tag with type METADATA
      # Convenience subclass of TagObject that sets type to METADATA
      class MetadataTag < Conductor::Http::Models::TagObject
        def initialize(key:, value:)
          super(key: key, type: Conductor::Http::Models::TagType::METADATA, value: value)
        end
      end
    end
  end
end
