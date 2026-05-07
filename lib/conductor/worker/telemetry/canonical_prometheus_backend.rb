# frozen_string_literal: true

module Conductor
  module Worker
    module Telemetry
      # CanonicalPrometheusBackend - Prometheus backend for the canonical SDK metric catalog.
      #
      # Pre-registers every metric from the harmonization spec with its canonical
      # label set and bucket configuration. Uses camelCase domain labels (taskType,
      # workflowType) per the canonical convention.
      class CanonicalPrometheusBackend
        TIME_BUCKETS = [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10].freeze
        SIZE_BUCKETS = [100, 1000, 10_000, 100_000, 1_000_000, 10_000_000].freeze

        COUNTER_LABELS = {
          'task_poll_total' => %i[taskType],
          'task_execution_started_total' => %i[taskType],
          'task_poll_error_total' => %i[taskType exception],
          'task_execute_error_total' => %i[taskType exception],
          'task_update_error_total' => %i[taskType exception],
          'task_paused_total' => %i[taskType],
          'thread_uncaught_exceptions_total' => %i[exception],
          'workflow_start_error_total' => %i[workflowType exception]
        }.freeze

        HISTOGRAM_LABELS = {
          'task_poll_time_seconds' => %i[taskType status],
          'task_execute_time_seconds' => %i[taskType status],
          'task_update_time_seconds' => %i[taskType status],
          'http_api_client_request_seconds' => %i[method uri status],
          'task_result_size_bytes' => %i[taskType],
          'workflow_input_size_bytes' => %i[workflowType version]
        }.freeze

        GAUGE_LABELS = {
          'active_workers' => %i[taskType]
        }.freeze

        HISTOGRAM_BUCKETS = {
          'task_result_size_bytes' => SIZE_BUCKETS,
          'workflow_input_size_bytes' => SIZE_BUCKETS
        }.freeze

        def initialize(registry: nil)
          load_prometheus_client
          @registry = registry || Prometheus::Client.registry
          @counters = {}
          @histograms = {}
          @gauges = {}
          setup_metrics
        end

        def increment(name, labels: {}, value: 1)
          metric = get_or_create_counter(name)
          metric.increment(labels: normalize_labels(name, labels, COUNTER_LABELS), by: value)
        end

        def observe(name, value, labels: {})
          metric = get_or_create_histogram(name)
          metric.observe(value, labels: normalize_labels(name, labels, HISTOGRAM_LABELS))
        end

        def set(name, value, labels: {})
          metric = get_or_create_gauge(name)
          metric.set(value, labels: normalize_labels(name, labels, GAUGE_LABELS))
        end

        attr_reader :registry

        private

        def load_prometheus_client
          require 'prometheus/client'
        rescue LoadError
          raise ConfigurationError,
                "The 'prometheus-client' gem is required for Prometheus metrics. " \
                "Add `gem 'prometheus-client'` to your Gemfile."
        end

        def setup_metrics
          COUNTER_LABELS.each do |name, _|
            register_counter(name, "Counter for #{name}")
          end

          HISTOGRAM_LABELS.each do |name, _|
            register_histogram(name, "Histogram for #{name}")
          end

          GAUGE_LABELS.each do |name, _|
            register_gauge(name, "Gauge for #{name}")
          end
        end

        def register_counter(name, docstring)
          metric_name = name.to_sym
          labels = COUNTER_LABELS.fetch(name, %i[taskType])
          @counters[name] = register_or_reuse(metric_name) do
            Prometheus::Client::Counter.new(metric_name, docstring: docstring, labels: labels)
          end
        end

        def register_histogram(name, docstring)
          metric_name = name.to_sym
          labels = HISTOGRAM_LABELS.fetch(name, %i[taskType])
          buckets = HISTOGRAM_BUCKETS[name] || TIME_BUCKETS
          @histograms[name] = register_or_reuse(metric_name) do
            Prometheus::Client::Histogram.new(metric_name, docstring: docstring,
                                                           labels: labels, buckets: buckets)
          end
        end

        def register_gauge(name, docstring)
          metric_name = name.to_sym
          labels = GAUGE_LABELS.fetch(name, %i[taskType])
          @gauges[name] = register_or_reuse(metric_name) do
            Prometheus::Client::Gauge.new(metric_name, docstring: docstring, labels: labels)
          end
        end

        def register_or_reuse(metric_name)
          if @registry.exist?(metric_name)
            @registry.get(metric_name)
          else
            metric = yield
            @registry.register(metric)
            metric
          end
        end

        def get_or_create_counter(name)
          @counters[name] ||= register_or_reuse(name.to_sym) do
            labels = COUNTER_LABELS.fetch(name, %i[taskType])
            Prometheus::Client::Counter.new(name.to_sym, docstring: "Counter for #{name}", labels: labels)
          end
        end

        def get_or_create_histogram(name)
          @histograms[name] ||= register_or_reuse(name.to_sym) do
            labels = HISTOGRAM_LABELS.fetch(name, %i[taskType])
            buckets = HISTOGRAM_BUCKETS[name] || TIME_BUCKETS
            Prometheus::Client::Histogram.new(name.to_sym, docstring: "Histogram for #{name}",
                                                           labels: labels, buckets: buckets)
          end
        end

        def get_or_create_gauge(name)
          @gauges[name] ||= register_or_reuse(name.to_sym) do
            labels = GAUGE_LABELS.fetch(name, %i[taskType])
            Prometheus::Client::Gauge.new(name.to_sym, docstring: "Gauge for #{name}", labels: labels)
          end
        end

        # Align provided labels to the declared label set for the metric.
        # Missing keys get empty-string defaults; unknown keys are dropped.
        def normalize_labels(name, labels, schema)
          symbolized = {}
          labels.each do |key, value|
            next if value.nil?

            symbolized[key.to_sym] = value.to_s
          end

          declared = schema[name]
          return symbolized unless declared

          declared.each_with_object({}) do |key, acc|
            acc[key] = symbolized.key?(key) ? symbolized[key] : ''
          end
        end
      end
    end
  end
end
