# frozen_string_literal: true

require_relative '../events/listeners'

module Conductor
  module Worker
    module Telemetry
      # LegacyMetricsCollector - The original Ruby SDK metrics implementation.
      #
      # Emits the pre-harmonization metric set with snake_case labels (task_type, error).
      # This is the default implementation during the deprecation period while
      # WORKER_CANONICAL_METRICS defaults to false.
      #
      # Canonical-only event handlers (on_task_update_completed, on_task_paused, etc.)
      # are implemented as no-ops so this collector satisfies the full listener interface
      # and can be used interchangeably with CanonicalMetricsCollector.
      class LegacyMetricsCollector
        include Events::TaskRunnerEventsListener
        include Events::WorkflowEventsListener
        include Events::HttpEventsListener

        def initialize(backend: :null)
          @backend = load_backend(backend)
        end

        attr_reader :backend

        # --- Real legacy metrics ---

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

        def on_task_execution_started(_event)
          # No legacy metric for execution-started
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

        # --- No-op stubs for canonical-only events ---

        def on_task_update_completed(_event); end
        def on_task_paused(_event); end
        def on_thread_uncaught_exception(_event); end
        def on_active_workers_changed(_event); end
        def on_workflow_start_error(_event); end
        def on_workflow_input_size(_event); end
        def on_http_api_request(_event); end

        private

        def load_backend(backend)
          case backend
          when :null, nil
            NullBackend.new
          when :prometheus
            load_prometheus_backend
          else
            backend
          end
        end

        def load_prometheus_backend
          require_relative 'prometheus_backend'
          PrometheusBackend.new
        rescue LoadError
          raise ConfigurationError,
                "The 'prometheus-client' gem is required for Prometheus metrics. " \
                "Add `gem 'prometheus-client'` to your Gemfile."
        end
      end
    end
  end
end
