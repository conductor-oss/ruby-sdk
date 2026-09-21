# frozen_string_literal: true

require 'spec_helper'

# Pins the HTTP verb contract for the scheduler resource. The two per-schedule
# pause/resume routes are mapped differently by the two server families:
#
#   - OSS Conductor maps them PUT-only (`@PutMapping` in SchedulerResource.java).
#   - Orkes Conductor accepts both GET and PUT as of the dual
#     `@RequestMapping(method = {GET, PUT})` added in 2026-07; deployments older
#     than that are GET-only.
#
# Hence PUT first, falling back to GET on a 405 -- and only on a 405. The
# admin/bulk endpoints are GET on both families and must never be sent as PUT.
#
# This mirrors the equivalent guards in the other SDKs
# (python-sdk tests/unit/orkes/test_scheduler_resource_contract.py,
# go-sdk sdk/client/api_scheduler_resource_test.go,
# rust-sdk tests/scheduler_verb_fallback_tests.rs,
# csharp-sdk Tests/ApiUnit/SchedulerResourceApiUnitTest.cs).
RSpec.describe Conductor::Http::Api::SchedulerResourceApi do
  let(:api_client) { instance_double(Conductor::Http::ApiClient) }
  let(:api) { described_class.new(api_client) }

  def method_not_allowed
    Conductor::ApiError.new(status: 405, reason: 'Method Not Allowed')
  end

  describe 'per-schedule pause/resume verb fallback' do
    describe '#pause_schedule' do
      it 'sends PUT first' do
        expect(api_client).to receive(:call_api).with(
          '/scheduler/schedules/{name}/pause',
          'PUT',
          hash_including(path_params: { name: 'sched-1' })
        )

        api.pause_schedule('sched-1')
      end

      it 'falls back to GET on the same path when the server answers 405' do
        expect(api_client).to receive(:call_api)
          .with('/scheduler/schedules/{name}/pause', 'PUT', any_args)
          .and_raise(method_not_allowed)
        expect(api_client).to receive(:call_api).with(
          '/scheduler/schedules/{name}/pause',
          'GET',
          hash_including(path_params: { name: 'sched-1' })
        )

        api.pause_schedule('sched-1')
      end
    end

    describe '#resume_schedule' do
      it 'sends PUT first' do
        expect(api_client).to receive(:call_api).with(
          '/scheduler/schedules/{name}/resume',
          'PUT',
          hash_including(path_params: { name: 'sched-1' })
        )

        api.resume_schedule('sched-1')
      end

      it 'falls back to GET on the same path when the server answers 405' do
        expect(api_client).to receive(:call_api)
          .with('/scheduler/schedules/{name}/resume', 'PUT', any_args)
          .and_raise(method_not_allowed)
        expect(api_client).to receive(:call_api).with(
          '/scheduler/schedules/{name}/resume',
          'GET',
          hash_including(path_params: { name: 'sched-1' })
        )

        api.resume_schedule('sched-1')
      end
    end

    it 'does not memoize the dialect: every call attempts PUT first' do
      verbs = []
      allow(api_client).to receive(:call_api) do |_path, verb, *_rest|
        verbs << verb
        raise method_not_allowed if verb == 'PUT'
      end

      api.pause_schedule('sched-1')
      api.pause_schedule('sched-2')

      expect(verbs).to eq(%w[PUT GET PUT GET])
    end

    # Only a 405 means "wrong verb for this route". A 404/403/500 is a real
    # failure and re-sending it as a GET would mask it.
    [404, 403, 500].each do |status|
      it "propagates a #{status} without falling back to GET" do
        error = Conductor::ApiError.new(status: status, reason: 'nope')
        expect(api_client).to receive(:call_api)
          .with('/scheduler/schedules/{name}/pause', 'PUT', any_args)
          .once
          .and_raise(error)

        expect { api.pause_schedule('sched-1') }.to raise_error(Conductor::ApiError) { |e|
          expect(e.status).to eq(status)
        }
      end
    end
  end

  # The admin endpoints are GET on both server families -- they are not part of
  # the verb split and must not acquire a PUT attempt.
  describe 'admin/bulk endpoints stay GET' do
    it '#pause_all_schedules sends GET' do
      expect(api_client).to receive(:call_api).with('/scheduler/admin/pause', 'GET', any_args)
      api.pause_all_schedules
    end

    it '#resume_all_schedules sends GET' do
      expect(api_client).to receive(:call_api).with('/scheduler/admin/resume', 'GET', any_args)
      api.resume_all_schedules
    end
  end
end
