# frozen_string_literal: true

require 'json'
require_relative '../http/models/task_def'
require_relative '../client/metadata_client'

module Conductor
  module Worker
    # TaskDefinitionRegistrar - Handles automatic task definition registration
    # Generates JSON schemas from worker function signatures and registers
    # task definitions with the Conductor server.
    class TaskDefinitionRegistrar
      # @param configuration [Configuration] Conductor configuration
      # @param logger [Logger] Logger instance
      def initialize(configuration, logger: nil)
        @configuration = configuration
        @metadata_client = Client::MetadataClient.new(configuration)
        @logger = logger || Logger.new($stdout)
      end

      # Register a task definition for a worker
      # @param worker [Worker] The worker instance
      # @return [Boolean] True if registration succeeded
      def register(worker)
        return false unless worker.register_task_def

        task_def = build_task_definition(worker)

        # Generate schemas if worker has typed parameters
        input_schema = generate_input_schema(worker)
        output_schema = generate_output_schema(worker)

        # Register schemas if available
        register_schemas(worker.task_definition_name, input_schema, output_schema) if input_schema || output_schema

        # Register or update task definition
        if worker.overwrite_task_def
          register_or_update_task_def(task_def)
        else
          register_if_not_exists(task_def)
        end

        @logger.info("Registered task definition: #{worker.task_definition_name}")
        true
      rescue StandardError => e
        @logger.warn("Failed to register task definition '#{worker.task_definition_name}': #{e.message}")
        false
      end

      private

      # Build a TaskDef from worker configuration
      # @param worker [Worker] The worker instance
      # @return [TaskDef]
      def build_task_definition(worker)
        task_def = worker.task_def_template&.dup || Http::Models::TaskDef.new

        task_def.name = worker.task_definition_name

        # Set reasonable defaults if not provided
        task_def.retry_count ||= 3
        task_def.retry_logic ||= Http::Models::TaskDef::RetryLogic::FIXED
        task_def.timeout_policy ||= Http::Models::TaskDef::TaskTimeoutPolicy::TIME_OUT_WF
        task_def.timeout_seconds ||= 60
        task_def.response_timeout_seconds ||= 60

        task_def
      end

      # Generate JSON Schema for worker input parameters
      # @param worker [Worker] The worker instance
      # @return [Hash, nil] JSON Schema or nil
      def generate_input_schema(worker)
        return nil unless worker.execute_function.respond_to?(:parameters)

        params = worker.execute_function.parameters
        return nil if params.empty?

        # Skip if first param is a positional arg (takes full Task object)
        first_type = params.first&.first
        return nil if %i[req opt rest].include?(first_type)

        properties = {}
        required = []

        params.each do |type, name|
          next unless name

          prop_name = name.to_s

          case type
          when :keyreq # Required keyword argument
            properties[prop_name] = infer_property_schema(name)
            required << prop_name
          when :key # Optional keyword argument
            properties[prop_name] = infer_property_schema(name)
          when :keyrest # **kwargs
            # Can't generate schema for **kwargs
            return nil
          end
        end

        return nil if properties.empty?

        schema = {
          '$schema' => 'http://json-schema.org/draft-07/schema#',
          'type' => 'object',
          'title' => "#{worker.task_definition_name}_input",
          'properties' => properties
        }

        schema['required'] = required unless required.empty?
        schema['additionalProperties'] = !worker.strict_schema

        schema
      end

      # Generate JSON Schema for worker output
      # @param worker [Worker] The worker instance
      # @return [Hash, nil] JSON Schema or nil
      def generate_output_schema(_worker)
        # Output schema is harder to infer without return type annotations
        # In Ruby, we'd need Sorbet/RBS type annotations
        # For now, return nil (no output schema)
        nil
      end

      # Infer property schema from parameter name
      # Uses naming conventions to guess types
      # @param name [Symbol] Parameter name
      # @return [Hash] Property schema
      def infer_property_schema(name)
        name_str = name.to_s.downcase

        # Infer type from naming conventions
        type = if name_str.end_with?('_id', 'id', '_count', 'count', '_num', 'num', '_index', 'index')
                 'integer'
               elsif name_str.end_with?('_at', '_time', '_date')
                 'string' # ISO8601 date string
               elsif name_str.start_with?('is_', 'has_', 'can_', 'should_', 'enable')
                 'boolean'
               elsif name_str.end_with?('_amount', '_price', '_rate', '_percent')
                 'number'
               elsif name_str.end_with?('_list', '_items', '_array', '_ids')
                 'array'
               elsif name_str.end_with?('_data', '_config', '_options', '_params', '_payload')
                 'object'
               else
                 'string' # Default to string
               end

        schema = { 'type' => type }

        # Add format hints for certain types
        case name_str
        when /email/
          schema['format'] = 'email'
        when /url/, /uri/, /href/
          schema['format'] = 'uri'
        when /_at$/, /_time$/
          schema['format'] = 'date-time'
        when /_date$/
          schema['format'] = 'date'
        when /uuid/, /guid/
          schema['format'] = 'uuid'
        end

        schema
      end

      # Register schemas with the server
      # @param task_name [String] Task definition name
      # @param input_schema [Hash, nil] Input schema
      # @param output_schema [Hash, nil] Output schema
      def register_schemas(task_name, input_schema, output_schema)
        # NOTE: Schema registration requires Orkes Conductor
        # OSS Conductor may not have this endpoint

        if input_schema
          begin
            register_schema("#{task_name}_input", input_schema)
          rescue ApiError => e
            @logger.debug("Schema registration not available: #{e.message}") if e.status == 404
          end
        end

        return unless output_schema

        begin
          register_schema("#{task_name}_output", output_schema)
        rescue ApiError => e
          @logger.debug("Schema registration not available: #{e.message}") if e.status == 404
        end
      end

      # Register a single schema
      # @param name [String] Schema name
      # @param schema [Hash] JSON Schema
      def register_schema(name, _schema)
        # This would call the schema API if available
        # For now, just log
        @logger.debug("Would register schema: #{name}")
      end

      # Register task def, update if already exists
      # @param task_def [TaskDef]
      def register_or_update_task_def(task_def)
        @metadata_client.update_task_def(task_def)
      rescue ApiError => e
        raise unless e.status == 404

        # Task def doesn't exist, create it
        @metadata_client.register_task_def([task_def])
      end

      # Register task def only if it doesn't exist
      # @param task_def [TaskDef]
      def register_if_not_exists(task_def)
        existing = @metadata_client.get_task_def(task_def.name)
        @logger.info("Task definition '#{task_def.name}' already exists, skipping")
      rescue ApiError => e
        raise unless e.status == 404

        # Task def doesn't exist, create it
        @metadata_client.register_task_def([task_def])
      end
    end

    # JsonSchemaGenerator - Utility for generating JSON Schema from Ruby types
    # Can be extended to work with Sorbet types or RBS annotations
    class JsonSchemaGenerator
      # Ruby type to JSON Schema type mapping
      TYPE_MAP = {
        'String' => 'string',
        'Integer' => 'integer',
        'Float' => 'number',
        'Numeric' => 'number',
        'TrueClass' => 'boolean',
        'FalseClass' => 'boolean',
        'Array' => 'array',
        'Hash' => 'object',
        'NilClass' => 'null',
        'Time' => 'string',
        'Date' => 'string',
        'DateTime' => 'string'
      }.freeze

      # Generate JSON Schema from a Ruby value (for inference)
      # @param value [Object] A sample value
      # @return [Hash] JSON Schema
      def self.from_value(value)
        case value
        when String
          { 'type' => 'string' }
        when Integer
          { 'type' => 'integer' }
        when Float
          { 'type' => 'number' }
        when TrueClass, FalseClass
          { 'type' => 'boolean' }
        when Array
          if value.empty?
            { 'type' => 'array' }
          else
            { 'type' => 'array', 'items' => from_value(value.first) }
          end
        when Hash
          generate_object_schema(value)
        when Time, DateTime
          { 'type' => 'string', 'format' => 'date-time' }
        when Date
          { 'type' => 'string', 'format' => 'date' }
        when NilClass
          { 'type' => 'null' }
        else
          { 'type' => 'object' }
        end
      end

      # Generate schema from a hash with sample values
      # @param hash [Hash] Hash with sample values
      # @return [Hash] JSON Schema
      def self.generate_object_schema(hash)
        properties = {}
        hash.each do |key, value|
          properties[key.to_s] = from_value(value)
        end

        {
          'type' => 'object',
          'properties' => properties
        }
      end

      # Generate a schema from a Ruby class definition
      # Works with Struct, Data (Ruby 3.2+), or classes with attr_accessor
      # @param klass [Class] Ruby class
      # @return [Hash] JSON Schema
      def self.from_class(klass)
        properties = {}

        # Try to get attribute names
        if klass.respond_to?(:members)
          # Struct or Data
          klass.members.each do |attr|
            properties[attr.to_s] = { 'type' => 'string' }
          end
        elsif klass.instance_methods.include?(:to_h)
          # Has to_h, try to instantiate and inspect
          # Skip this for safety
        end

        {
          '$schema' => 'http://json-schema.org/draft-07/schema#',
          'type' => 'object',
          'title' => klass.name,
          'properties' => properties
        }
      end
    end
  end
end
