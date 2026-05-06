# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/conductor/worker/telemetry/metrics_collector'

RSpec.describe Conductor::Worker::Telemetry::MetricsCollector do
  describe '.create' do
    around do |example|
      old_val = ENV.fetch('WORKER_CANONICAL_METRICS', nil)
      example.run
    ensure
      if old_val.nil?
        ENV.delete('WORKER_CANONICAL_METRICS')
      else
        ENV['WORKER_CANONICAL_METRICS'] = old_val
      end
    end

    it 'returns a LegacyMetricsCollector by default' do
      ENV.delete('WORKER_CANONICAL_METRICS')
      collector = described_class.create
      expect(collector).to be_a(Conductor::Worker::Telemetry::LegacyMetricsCollector)
    end

    it 'returns a LegacyMetricsCollector when WORKER_CANONICAL_METRICS is false' do
      ENV['WORKER_CANONICAL_METRICS'] = 'false'
      collector = described_class.create
      expect(collector).to be_a(Conductor::Worker::Telemetry::LegacyMetricsCollector)
    end

    it 'returns a CanonicalMetricsCollector when WORKER_CANONICAL_METRICS is true' do
      ENV['WORKER_CANONICAL_METRICS'] = 'true'
      collector = described_class.create(subscribe_global_http: false)
      expect(collector).to be_a(Conductor::Worker::Telemetry::CanonicalMetricsCollector)
    end

    it 'accepts "1" as truthy for WORKER_CANONICAL_METRICS' do
      ENV['WORKER_CANONICAL_METRICS'] = '1'
      collector = described_class.create(subscribe_global_http: false)
      expect(collector).to be_a(Conductor::Worker::Telemetry::CanonicalMetricsCollector)
    end

    it 'accepts "yes" as truthy for WORKER_CANONICAL_METRICS' do
      ENV['WORKER_CANONICAL_METRICS'] = 'yes'
      collector = described_class.create(subscribe_global_http: false)
      expect(collector).to be_a(Conductor::Worker::Telemetry::CanonicalMetricsCollector)
    end

    it 'is case-insensitive for WORKER_CANONICAL_METRICS' do
      ENV['WORKER_CANONICAL_METRICS'] = 'TRUE'
      collector = described_class.create(subscribe_global_http: false)
      expect(collector).to be_a(Conductor::Worker::Telemetry::CanonicalMetricsCollector)
    end

    it 'passes backend option through to the collector' do
      ENV.delete('WORKER_CANONICAL_METRICS')
      collector = described_class.create(backend: :null)
      expect(collector.backend).to be_a(Conductor::Worker::Telemetry::NullBackend)
    end

    it 'legacy collector returns "legacy" from collector_name' do
      ENV.delete('WORKER_CANONICAL_METRICS')
      collector = described_class.create
      expect(collector.collector_name).to eq('legacy')
    end

    it 'canonical collector returns "canonical" from collector_name' do
      ENV['WORKER_CANONICAL_METRICS'] = 'true'
      collector = described_class.create(subscribe_global_http: false)
      expect(collector.collector_name).to eq('canonical')
    end
  end

  describe '.canonical_metrics_enabled?' do
    around do |example|
      old_val = ENV.fetch('WORKER_CANONICAL_METRICS', nil)
      example.run
    ensure
      if old_val.nil?
        ENV.delete('WORKER_CANONICAL_METRICS')
      else
        ENV['WORKER_CANONICAL_METRICS'] = old_val
      end
    end

    it 'returns false by default' do
      ENV.delete('WORKER_CANONICAL_METRICS')
      expect(described_class.canonical_metrics_enabled?).to be false
    end

    it 'returns true when set to "true"' do
      ENV['WORKER_CANONICAL_METRICS'] = 'true'
      expect(described_class.canonical_metrics_enabled?).to be true
    end

    it 'returns false for arbitrary strings' do
      ENV['WORKER_CANONICAL_METRICS'] = 'maybe'
      expect(described_class.canonical_metrics_enabled?).to be false
    end
  end
end

RSpec.describe Conductor::Worker::Telemetry::NullBackend do
  let(:backend) { described_class.new }

  describe '#increment' do
    it 'is a no-op' do
      expect { backend.increment('metric', labels: { foo: 'bar' }) }.not_to raise_error
    end
  end

  describe '#observe' do
    it 'is a no-op' do
      expect { backend.observe('metric', 123, labels: { foo: 'bar' }) }.not_to raise_error
    end
  end

  describe '#set' do
    it 'is a no-op' do
      expect { backend.set('metric', 456, labels: { foo: 'bar' }) }.not_to raise_error
    end
  end
end
