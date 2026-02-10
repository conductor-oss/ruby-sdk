# frozen_string_literal: true

require 'socket'

module Conductor
  module Worker
    # Configuration resolver for workers with 3-tier hierarchy
    # Priority (highest to lowest):
    # 1. Worker-specific env var: conductor.worker.{task_name}.{property}
    # 2. Global worker env var: conductor.worker.all.{property}
    # 3. Code-level default from worker definition
    class WorkerConfig
      # Configuration properties with their types and default values
      PROPERTIES = {
        poll_interval: { type: :integer, default: 100 },       # milliseconds
        thread_count: { type: :integer, default: 1 },
        domain: { type: :string, default: nil },
        worker_id: { type: :string, default: nil },            # auto-generated if nil
        poll_timeout: { type: :integer, default: 100 },        # milliseconds
        register_task_def: { type: :boolean, default: false },
        overwrite_task_def: { type: :boolean, default: true },
        strict_schema: { type: :boolean, default: false },
        paused: { type: :boolean, default: false },
        isolation: { type: :symbol, default: :thread },        # :thread or :ractor
        executor: { type: :symbol, default: :thread_pool }     # :thread_pool or :fiber
      }.freeze

      class << self
        # Resolve configuration for a worker
        # @param worker_name [String] Task definition name
        # @param defaults [Hash] Code-level defaults from worker definition
        # @return [Hash] Resolved configuration
        def resolve(worker_name, defaults = {})
          result = {}

          PROPERTIES.each do |property, config|
            # Try to get from environment variables (3-tier hierarchy)
            env_value = get_env_value(worker_name, property)

            result[property] = if env_value
                                 convert_value(env_value, config[:type])
                               elsif defaults.key?(property)
                                 defaults[property]
                               else
                                 config[:default]
                               end
          end

          # Auto-generate worker_id if not set
          result[:worker_id] ||= generate_worker_id

          result
        end

        # Generate a unique worker ID
        # @return [String]
        def generate_worker_id
          hostname = begin
            Socket.gethostname
          rescue StandardError
            'unknown'
          end
          pid = Process.pid
          thread_id = Thread.current.object_id.to_s(16)
          "#{hostname}-#{pid}-#{thread_id}"
        end

        private

        # Get a value from environment variables using the 3-tier hierarchy
        # @param worker_name [String] Task definition name
        # @param property [Symbol] Property name
        # @return [String, nil] Value from environment or nil
        def get_env_value(worker_name, property)
          property_str = property.to_s
          worker_name_normalized = normalize_worker_name(worker_name)

          # Priority 1: Worker-specific env vars
          # conductor.worker.{task_name}.{property} (dotted format)
          value = ENV.fetch("conductor.worker.#{worker_name}.#{property_str}", nil)
          return value if value

          # CONDUCTOR_WORKER_{TASK_NAME}_{PROPERTY} (uppercase format)
          value = ENV.fetch("CONDUCTOR_WORKER_#{worker_name_normalized}_#{property_str.upcase}", nil)
          return value if value

          # Priority 2: Global worker env vars
          # conductor.worker.all.{property} (dotted format)
          value = ENV.fetch("conductor.worker.all.#{property_str}", nil)
          return value if value

          # CONDUCTOR_WORKER_ALL_{PROPERTY} (uppercase format)
          value = ENV.fetch("CONDUCTOR_WORKER_ALL_#{property_str.upcase}", nil)
          return value if value

          # Priority 3: Legacy format
          # CONDUCTOR_WORKER_{PROPERTY} (old global format)
          value = ENV.fetch("CONDUCTOR_WORKER_#{property_str.upcase}", nil)
          return value if value

          # Special backward compatibility for poll_interval
          if property == :poll_interval
            value = ENV.fetch('POLLING_INTERVAL', nil)
            return value if value
          end

          nil
        end

        # Normalize worker name for environment variable lookup
        # Converts task names like "my-task" to "MY_TASK"
        # @param name [String] Worker name
        # @return [String] Normalized name
        def normalize_worker_name(name)
          name.to_s.gsub(/[^a-zA-Z0-9]/, '_').upcase
        end

        # Convert a string value to the appropriate type
        # @param value [String] String value from environment
        # @param type [Symbol] Target type (:integer, :boolean, :string, :symbol)
        # @return [Object] Converted value
        def convert_value(value, type)
          case type
          when :integer
            value.to_i
          when :boolean
            parse_boolean(value)
          when :symbol
            value.to_sym
          when :string
            value
          else
            value
          end
        end

        # Parse a boolean value from string
        # Accepts: true/1/yes and false/0/no (case-insensitive)
        # @param value [String] String value
        # @return [Boolean]
        def parse_boolean(value)
          case value.to_s.downcase
          when 'true', '1', 'yes'
            true
          when 'false', '0', 'no'
            false
          else
            false
          end
        end
      end
    end
  end
end
