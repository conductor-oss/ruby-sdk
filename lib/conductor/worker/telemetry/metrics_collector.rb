# frozen_string_literal: true

require_relative '../events/listeners'

module Conductor
  module Worker
    module Telemetry
      # MetricsCollector - Collects metrics from worker events
      # Implements TaskRunnerEventsListener protocol
      # Uses pluggable backends (null, prometheus, etc.)
      class MetricsCollector
        include Events::TaskRunnerEventsListener

        # Initialize metrics collector
        # @param backend [Symbol, Object] Backend type (:null, :prometheus) or custom backend
        def initialize(backend: :null)
          @backend = load_backend(backend)
        end

        # @return [Object] The metrics backend
        attr_reader :backend

        # --- Event Handlers ---

        def on_poll_started(event)
          @backend.increment('task_poll_total', labels: { task_type: event.task_type })
        end

        def on_poll_completed(event)
          @backend.observe('task_poll_time_seconds', event.duration_ms / 1000.0,
                           labels: { task_type: event.task_type })
        end

        def on_poll_failure(event)
          @backend.increment('task_poll_error_total',
                             labels: {
                               task_type: event.task_type,
                               error: event.cause.class.name
                             })
        end

        def on_task_execution_started(event)
          # Could track active tasks here
        end

        def on_task_execution_completed(event)
          @backend.observe('task_execute_time_seconds', event.duration_ms / 1000.0,
                           labels: { task_type: event.task_type })

          return unless event.output_size_bytes

          @backend.observe('task_result_size_bytes', event.output_size_bytes,
                           labels: { task_type: event.task_type })
        end

        def on_task_execution_failure(event)
          @backend.increment('task_execute_error_total',
                             labels: {
                               task_type: event.task_type,
                               exception: event.cause.class.name,
                               retryable: event.is_retryable.to_s
                             })
        end

        def on_task_update_failure(event)
          @backend.increment('task_update_failed_total',
                             labels: { task_type: event.task_type })
        end

        private

        # Load a metrics backend
        # @param backend [Symbol, Object] Backend type or instance
        # @return [Object] Backend instance
        def load_backend(backend)
          case backend
          when :null, nil
            NullBackend.new
          when :prometheus
            load_prometheus_backend
          else
            # Assume it's a custom backend instance
            backend
          end
        end

        # Load Prometheus backend (lazy loading)
        # @return [PrometheusBackend]
        def load_prometheus_backend
          require_relative 'prometheus_backend'
          PrometheusBackend.new
        rescue LoadError
          raise ConfigurationError,
                "The 'prometheus-client' gem is required for Prometheus metrics. " \
                "Add `gem 'prometheus-client'` to your Gemfile."
        end
      end

      # NullBackend - No-op backend for metrics
      # Used when metrics are disabled or not configured
      class NullBackend
        # Increment a counter (no-op)
        # @param name [String] Metric name
        # @param labels [Hash] Metric labels
        def increment(name, labels: {})
          # No-op
        end

        # Observe a value (no-op)
        # @param name [String] Metric name
        # @param value [Numeric] Value to observe
        # @param labels [Hash] Metric labels
        def observe(name, value, labels: {})
          # No-op
        end

        # Set a gauge value (no-op)
        # @param name [String] Metric name
        # @param value [Numeric] Value to set
        # @param labels [Hash] Metric labels
        def set(name, value, labels: {})
          # No-op
        end
      end
    end
  end
end
