# frozen_string_literal: true

module Conductor
  module Worker
    module Telemetry
      # PrometheusBackend - Prometheus metrics backend
      # Uses the prometheus-client gem for metric collection.
      #
      # Emits the canonical Conductor SDK worker metric catalog
      # (see https://github.com/orkes-io/certification-cloud-util/blob/main/sdk-metrics-harmonization.md)
      # alongside a few
      # Ruby-legacy series that are retained to keep existing dashboards working
      # through Phase 1 of the harmonization.
      #
      # Canonical metrics emitted:
      # - task_poll_total{taskType, task_type} (Counter)
      # - task_execution_started_total{taskType} (Counter, canonical-only — new to Ruby)
      # - task_poll_error_total{taskType, task_type, exception, error} (Counter)
      # - task_execute_error_total{taskType, task_type, exception, retryable} (Counter)
      # - task_update_error_total{taskType, task_type, exception} (Counter)
      # - task_paused_total{taskType} (Counter, canonical-only — new to Ruby)
      # - thread_uncaught_exceptions_total{exception} (Counter)
      # - workflow_start_error_total{workflowType, exception} (Counter)
      # - task_poll_time_seconds{taskType, task_type, status} (Histogram)
      # - task_execute_time_seconds{taskType, task_type, status} (Histogram)
      # - task_update_time_seconds{taskType, status} (Histogram, canonical-only — new to Ruby)
      # - http_api_client_request_seconds{method, uri, status} (Histogram)
      # - task_result_size_bytes{taskType} (Gauge, last-value, canonical-only — new to Ruby)
      # - workflow_input_size_bytes{workflowType, version} (Gauge, last-value)
      # - active_workers{taskType, task_type} (Gauge, last-value)
      #
      # Legacy metrics retained for backward-compatibility during Phase 1:
      # - task_update_failed_total{task_type} (Counter; deprecated alias of task_update_error_total)
      # - task_result_size_bytes_histogram{task_type} (Histogram; the pre-harmonization shape of
      #   task_result_size_bytes, renamed so the canonical name can carry the Gauge)
      #
      # @example
      #   collector = MetricsCollector.new(backend: :prometheus)
      #   # Metrics available at default prometheus registry
      class PrometheusBackend
        # Canonical time histogram buckets (seconds) from the harmonization doc
        TIME_BUCKETS = [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10].freeze

        # Size histogram buckets (bytes) - Ruby-specific; used only by the retained
        # legacy task_result_size_bytes_histogram
        SIZE_BUCKETS = [100, 1000, 10_000, 100_000, 1_000_000, 10_000_000].freeze

        # Metric name -> label keys (Symbols) for all pre-registered Counters
        COUNTER_LABELS = {
          'task_poll_total' => %i[taskType task_type],
          'task_execution_started_total' => %i[taskType],
          'task_poll_error_total' => %i[taskType task_type exception error],
          'task_execute_error_total' => %i[taskType task_type exception retryable],
          'task_update_error_total' => %i[taskType task_type exception],
          'task_update_failed_total' => %i[task_type],
          'task_paused_total' => %i[taskType],
          'thread_uncaught_exceptions_total' => %i[exception],
          'workflow_start_error_total' => %i[workflowType exception]
        }.freeze

        # Metric name -> label keys (Symbols) for all pre-registered Histograms
        HISTOGRAM_LABELS = {
          'task_poll_time_seconds' => %i[taskType task_type status],
          'task_execute_time_seconds' => %i[taskType task_type status],
          'task_update_time_seconds' => %i[taskType status],
          'http_api_client_request_seconds' => %i[method uri status],
          'task_result_size_bytes_histogram' => %i[task_type]
        }.freeze

        # Metric name -> label keys (Symbols) for all pre-registered Gauges
        GAUGE_LABELS = {
          'task_result_size_bytes' => %i[taskType],
          'workflow_input_size_bytes' => %i[workflowType version],
          'active_workers' => %i[taskType task_type]
        }.freeze

        # Histogram name -> bucket set. Names not present here fall back to TIME_BUCKETS
        # via #buckets_for(name).
        HISTOGRAM_BUCKETS = {
          'task_result_size_bytes_histogram' => SIZE_BUCKETS
        }.freeze

        # @return [Array<Numeric>] Bucket set for the given histogram name
        def self.buckets_for(name)
          HISTOGRAM_BUCKETS[name] || TIME_BUCKETS
        end

        def initialize(registry: nil)
          load_prometheus_client
          @registry = registry || Prometheus::Client.registry
          setup_metrics
        end

        # Increment a counter
        # @param name [String] Metric name
        # @param labels [Hash] Metric labels
        # @param value [Integer] Value to increment by (default: 1)
        def increment(name, labels: {}, value: 1)
          metric = get_or_create_counter(name)
          metric.increment(labels: normalize_labels(name, labels, COUNTER_LABELS), by: value)
        end

        # Observe a value in a histogram
        # @param name [String] Metric name
        # @param value [Numeric] Value to observe
        # @param labels [Hash] Metric labels
        def observe(name, value, labels: {})
          metric = get_or_create_histogram(name)
          metric.observe(value, labels: normalize_labels(name, labels, HISTOGRAM_LABELS))
        end

        # Set a gauge value
        # @param name [String] Metric name
        # @param value [Numeric] Value to set
        # @param labels [Hash] Metric labels
        def set(name, value, labels: {})
          metric = get_or_create_gauge(name)
          metric.set(value, labels: normalize_labels(name, labels, GAUGE_LABELS))
        end

        # Get the prometheus registry
        # @return [Prometheus::Client::Registry]
        attr_reader :registry

        private

        # Load prometheus-client gem
        def load_prometheus_client
          require 'prometheus/client'
        rescue LoadError
          raise ConfigurationError,
                "The 'prometheus-client' gem is required for Prometheus metrics. " \
                "Add `gem 'prometheus-client'` to your Gemfile."
        end

        # Pre-register every canonical + legacy metric with its precise label set
        # so `@registry` is predictable at process startup. get_or_create_* paths
        # still exist as a safety net for user-defined metrics.
        def setup_metrics
          @counters = {}
          @histograms = {}
          @gauges = {}

          register_counter('task_poll_total', 'Total number of task polls')
          register_counter('task_execution_started_total',
                           'Number of polled tasks dispatched to the worker function')
          register_counter('task_poll_error_total', 'Total number of poll errors')
          register_counter('task_execute_error_total', 'Total number of execution errors')
          register_counter('task_update_error_total',
                           'Total number of task update failures (after all retries exhausted)')
          register_counter('task_update_failed_total',
                           '[DEPRECATED] Alias of task_update_error_total kept for Phase 1 backward-compatibility')
          register_counter('task_paused_total', 'Number of poll iterations skipped because the worker is paused')
          register_counter('thread_uncaught_exceptions_total',
                           'Number of worker thread / runner uncaught exceptions')
          register_counter('workflow_start_error_total',
                           'Number of StartWorkflow calls that failed client-side')

          register_histogram('task_poll_time_seconds', 'Task poll duration in seconds')
          register_histogram('task_execute_time_seconds', 'Task execution duration in seconds')
          register_histogram('task_update_time_seconds', 'Task update duration in seconds')
          register_histogram('http_api_client_request_seconds',
                             'HTTP API client request duration in seconds')
          register_histogram('task_result_size_bytes_histogram',
                             '[DEPRECATED] Legacy Ruby-specific histogram shape of task_result_size_bytes')

          register_gauge('task_result_size_bytes', 'Most recent task result output size in bytes (last-value)')
          register_gauge('workflow_input_size_bytes', 'Most recent workflow input size in bytes (last-value)')
          register_gauge('active_workers',
                         'Number of worker threads/fibers currently executing a task (last-value)')
        end

        # Register a counter metric
        def register_counter(name, docstring)
          metric_name = name.to_sym
          labels = COUNTER_LABELS.fetch(name, %i[taskType task_type])
          @counters[name] = register_or_reuse(metric_name) do
            Prometheus::Client::Counter.new(metric_name, docstring: docstring, labels: labels)
          end
        end

        # Register a histogram metric
        def register_histogram(name, docstring)
          metric_name = name.to_sym
          labels = HISTOGRAM_LABELS.fetch(name, %i[taskType task_type])
          buckets = self.class.buckets_for(name)
          @histograms[name] = register_or_reuse(metric_name) do
            Prometheus::Client::Histogram.new(metric_name,
                                              docstring: docstring,
                                              labels: labels,
                                              buckets: buckets)
          end
        end

        # Register a gauge metric
        def register_gauge(name, docstring)
          metric_name = name.to_sym
          labels = GAUGE_LABELS.fetch(name, %i[taskType task_type])
          @gauges[name] = register_or_reuse(metric_name) do
            Prometheus::Client::Gauge.new(metric_name, docstring: docstring, labels: labels)
          end
        end

        # Either register a new metric (via the block) or reuse the existing one
        # if this process has already instantiated another PrometheusBackend (e.g.
        # in tests that share the default registry).
        # @yield [] block returning a newly-constructed Prometheus::Client metric
        def register_or_reuse(metric_name)
          if @registry.exist?(metric_name)
            @registry.get(metric_name)
          else
            metric = yield
            @registry.register(metric)
            metric
          end
        end

        # Get or create a counter metric
        def get_or_create_counter(name)
          @counters[name] ||= register_or_reuse(name.to_sym) do
            labels = COUNTER_LABELS.fetch(name, %i[taskType task_type])
            Prometheus::Client::Counter.new(name.to_sym,
                                            docstring: "Counter for #{name}",
                                            labels: labels)
          end
        end

        # Get or create a histogram metric
        def get_or_create_histogram(name)
          @histograms[name] ||= register_or_reuse(name.to_sym) do
            labels = HISTOGRAM_LABELS.fetch(name, %i[taskType task_type])
            buckets = HISTOGRAM_BUCKETS[name] ||
                      (name.include?('bytes') ? SIZE_BUCKETS : TIME_BUCKETS)
            Prometheus::Client::Histogram.new(name.to_sym,
                                              docstring: "Histogram for #{name}",
                                              labels: labels,
                                              buckets: buckets)
          end
        end

        # Get or create a gauge metric
        def get_or_create_gauge(name)
          @gauges[name] ||= register_or_reuse(name.to_sym) do
            labels = GAUGE_LABELS.fetch(name, %i[taskType task_type])
            Prometheus::Client::Gauge.new(name.to_sym,
                                          docstring: "Gauge for #{name}",
                                          labels: labels)
          end
        end

        # Normalize labels - coerce keys to symbols, filter out nil values, then
        # align the resulting hash to the registered label set for this metric:
        # missing keys are filled with empty strings, unknown keys are dropped.
        # This keeps the prometheus-client gem happy (it rejects mismatched label sets)
        # without requiring every caller to know every label key.
        # @param name [String] Metric name
        # @param labels [Hash] Input labels
        # @param schema [Hash<String, Array<Symbol>>] Per-metric declared label set
        # @return [Hash]
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

      # MetricsServer - HTTP server for exposing Prometheus metrics
      # Serves metrics at /metrics endpoint
      class MetricsServer
        DEFAULT_PORT = 9090

        # Initialize metrics server
        # @param port [Integer] Port to listen on (default: 9090)
        # @param registry [Prometheus::Client::Registry] Prometheus registry
        def initialize(port: DEFAULT_PORT, registry: nil)
          require 'prometheus/client'
          require 'prometheus/client/formats/text'
          require 'webrick'

          @port = port
          @registry = registry || Prometheus::Client.registry
          @server = nil
        end

        # Start the metrics server in a background thread
        # @return [Thread] Server thread
        def start
          @server = WEBrick::HTTPServer.new(
            Port: @port,
            Logger: WEBrick::Log.new('/dev/null'),
            AccessLog: []
          )

          @server.mount_proc '/metrics' do |_req, res|
            res.content_type = 'text/plain; version=0.0.4'
            res.body = Prometheus::Client::Formats::Text.marshal(@registry)
          end

          @server.mount_proc '/health' do |_req, res|
            res.content_type = 'application/json'
            res.body = '{"status":"healthy"}'
          end

          @thread = Thread.new { @server.start }
          @thread.name = 'prometheus-metrics-server'
          @thread
        end

        # Stop the metrics server
        def stop
          @server&.shutdown
          @thread&.join(5)
        end

        # @return [Integer] Server port
        attr_reader :port
      end
    end
  end
end
