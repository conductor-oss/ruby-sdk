# frozen_string_literal: true

require 'json'
require 'time'

module Conductor
  module Http
    module Models
      # Base class for all Conductor model objects
      # Implements the SWAGGER_TYPES pattern from Python SDK
      class BaseModel
        # Class method to define swagger types and attribute mappings
        def self.swagger_types
          self::SWAGGER_TYPES
        end

        def self.attribute_map
          self::ATTRIBUTE_MAP
        end

        # Convert model to hash using ATTRIBUTE_MAP for JSON keys
        def to_h
          hash = {}
          self.class.attribute_map.each do |attr, json_key|
            value = send(attr)
            next if value.nil?

            hash[json_key.to_s] = serialize_value(value)
          end
          hash
        end

        # Alias for to_h
        alias to_hash to_h

        # Convert model to JSON string
        def to_json(*_args)
          JSON.generate(to_h)
        end

        # Build model from hash (deserialization)
        def self.from_hash(hash)
          return nil unless hash
          # If it's not a Hash (e.g., a string expression like "${workflow.input.foo}"),
          # return it as-is rather than trying to deserialize
          return hash unless hash.is_a?(Hash)

          instance = new
          attribute_map.each do |attr, json_key|
            json_key_str = json_key.to_s
            next unless hash.key?(json_key_str) || hash.key?(json_key.to_sym)

            value = hash[json_key_str] || hash[json_key.to_sym]
            type = swagger_types[attr]

            instance.send("#{attr}=", deserialize_value(value, type))
          end
          instance
        end

        # Build model from JSON string
        def self.from_json(json_string)
          from_hash(JSON.parse(json_string))
        end

        private

        # Serialize a value for JSON output
        def serialize_value(value)
          case value
          when BaseModel
            value.to_h
          when Array
            value.map { |v| serialize_value(v) }
          when Hash
            value.transform_values { |v| serialize_value(v) }
          when Time, DateTime, Date
            value.iso8601
          else
            value
          end
        end

        # Deserialize a value based on type string
        def self.deserialize_value(value, type)
          return nil if value.nil?
          return value if type.nil?

          # Handle array types: "Array<Type>"
          if type.start_with?('Array<')
            inner_type = type[6..-2] # Extract Type from Array<Type>
            return value.map { |v| deserialize_value(v, inner_type) }
          end

          # Handle hash types: "Hash<String, Type>" or "Hash{String => Type}"
          if type.start_with?('Hash<', 'Hash{')
            # Extract value type from Hash<K, V> or Hash{K => V}
            match = type.match(/Hash[<{].*,\s*(.+)[>}]/)
            value_type = match[1] if match
            return value.transform_values { |v| deserialize_value(v, value_type) }
          end

          # Handle primitive types
          case type
          when 'String'
            value.to_s
          when 'Integer'
            value.to_i
          when 'Float'
            value.to_f
          when 'Boolean', 'BOOLEAN'
            value.to_s.downcase == 'true'
          when 'DateTime'
            parse_datetime(value)
          when 'Date'
            Date.parse(value.to_s)
          when 'Time'
            Time.parse(value.to_s)
          when 'Object'
            value
          else
            # Model class - convert to proper class
            deserialize_model(value, type)
          end
        end

        def self.parse_datetime(value)
          return value if value.is_a?(DateTime) || value.is_a?(Time)

          # Try ISO8601 first
          DateTime.iso8601(value.to_s)
        rescue ArgumentError
          # Fall back to regular parsing
          DateTime.parse(value.to_s)
        end

        def self.deserialize_model(value, type)
          # If value is not a Hash (e.g., a string expression), return as-is
          return value unless value.is_a?(Hash)

          # Try to find the model class
          klass = find_model_class(type)
          return value unless klass

          # If it's already the right type, return it
          return value if value.is_a?(klass)

          # Deserialize hash to model
          klass.respond_to?(:from_hash) ? klass.from_hash(value) : value
        end

        def self.find_model_class(type)
          # Try to find class in Conductor::Http::Models namespace
          const_name = type.split('::').last
          Conductor::Http::Models.const_get(const_name) if Conductor::Http::Models.const_defined?(const_name)
        rescue NameError
          nil
        end
      end
    end
  end
end
