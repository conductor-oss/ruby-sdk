# frozen_string_literal: true

module Conductor
  module Worker
    # Global registry for workers defined via worker_task DSL
    # Workers are registered when their defining code is loaded
    class WorkerRegistry
      class << self
        # Register a worker definition
        # @param task_definition_name [String] Task definition name
        # @param execute_function [Proc, Method] Function to execute tasks
        # @param options [Hash] Worker configuration options
        # @return [void]
        def register(task_definition_name, execute_function, options = {})
          key = [task_definition_name, options[:domain]]
          registry[key] = {
            task_definition_name: task_definition_name,
            execute_function: execute_function,
            options: options
          }
        end

        # Get all registered worker definitions
        # @return [Array<Hash>] Array of worker definition hashes
        def all
          registry.values
        end

        # Get a specific worker definition
        # @param task_definition_name [String] Task definition name
        # @param domain [String, nil] Optional domain
        # @return [Hash, nil] Worker definition or nil
        def get(task_definition_name, domain: nil)
          registry[[task_definition_name, domain]]
        end

        # Check if a worker is registered
        # @param task_definition_name [String] Task definition name
        # @param domain [String, nil] Optional domain
        # @return [Boolean]
        def registered?(task_definition_name, domain: nil)
          registry.key?([task_definition_name, domain])
        end

        # Clear all registered workers (primarily for testing)
        # @return [void]
        def clear
          @registry = {}
        end

        # Get the count of registered workers
        # @return [Integer]
        def count
          registry.size
        end

        # Get all registered task definition names
        # @return [Array<String>]
        def task_names
          registry.keys.map(&:first).uniq
        end

        private

        def registry
          @registry ||= {}
        end
      end
    end
  end
end
