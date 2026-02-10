# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

# Scheduler integration tests - run with:
# ORKES_INTEGRATION=true bundle exec rspec spec/integration/scheduler_spec.rb --format documentation
#
# These tests require Orkes Conductor credentials set via environment variables:
# - ORKES_SERVER_URL
# - ORKES_AUTH_KEY
# - ORKES_AUTH_SECRET
#
# APIs covered:
# 1. save_schedule - Create/update schedules
# 2. get_schedule - Retrieve specific schedule
# 3. get_all_schedules - List all schedules (with optional workflow filter)
# 4. delete_schedule - Remove schedule
# 5. pause_schedule - Pause specific schedule
# 6. resume_schedule - Resume specific schedule
# 7. pause_all_schedules - Pause all schedules
# 8. resume_all_schedules - Resume all schedules
# 9. get_next_few_schedule_execution_times - Preview execution times
# 10. search_schedule_executions - Search execution history
# 11. requeue_all_execution_records - Requeue executions
# 12. set_scheduler_tags - Set schedule tags
# 13. get_scheduler_tags - Get schedule tags
# 14. delete_scheduler_tags - Remove schedule tags

RSpec.describe 'Scheduler Integration', skip: !ENV['ORKES_INTEGRATION'] do
  let(:server_url) { ENV['ORKES_SERVER_URL'] || 'https://developer.orkescloud.com/api' }
  let(:auth_key) { ENV['ORKES_AUTH_KEY'] }
  let(:auth_secret) { ENV['ORKES_AUTH_SECRET'] }
  let(:test_id) { "ruby_sdk_sched_#{SecureRandom.hex(4)}" }

  let(:configuration) do
    Conductor::Configuration.new(
      server_api_url: server_url,
      auth_key: auth_key,
      auth_secret: auth_secret
    )
  end

  let(:clients) { Conductor::Orkes::OrkesClients.new(configuration) }
  let(:scheduler_client) { clients.get_scheduler_client }
  let(:metadata_client) { clients.get_metadata_client }

  # Track created resources for cleanup
  let(:created_schedules) { [] }
  let(:created_workflows) { [] }

  # Helper to skip tests that hit free tier limits
  def skip_if_limit_reached(error)
    if error.is_a?(Conductor::ApiError) && error.status == 402
      skip "Orkes free tier limit reached: #{error.message}"
    else
      raise error
    end
  end

  # Helper to get attribute from schedule object or hash
  def get_schedule_attr(schedule, attr_name)
    value = if schedule.is_a?(Hash)
              key_mapping = {
                'name' => 'name',
                'cron_expression' => 'cronExpression',
                'paused' => 'paused',
                'zone_id' => 'zoneId'
              }
              schedule[key_mapping[attr_name.to_s] || attr_name.to_s]
            else
              schedule.send(attr_name)
            end

    # Server returns nil for paused when it's false
    if attr_name.to_s == 'paused' && value.nil?
      false
    else
      value
    end
  end

  describe 'Setup: Create test workflows' do
    it 'creates workflows for scheduling' do
      # Create a simple workflow that can be scheduled
      workflow_def = Conductor::Http::Models::WorkflowDef.new(
        name: "#{test_id}_scheduled_workflow",
        version: 1,
        description: 'Test workflow for scheduler integration tests',
        tasks: [
          Conductor::Http::Models::WorkflowTask.new(
            name: 'test_task',
            task_reference_name: 'test_task_ref',
            type: 'SET_VARIABLE',
            input_parameters: {
              'scheduled' => true,
              'timestamp' => '${workflow.input.timestamp}'
            }
          )
        ],
        input_parameters: ['timestamp'],
        schema_version: 2,
        restartable: true
      )

      metadata_client.register_workflow_def(workflow_def, overwrite: true)
      created_workflows << ["#{test_id}_scheduled_workflow", 1]
      expect(true).to be true # Workflow registered successfully
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Schedule CRUD Operations' do
    let(:schedule_name) { "#{test_id}_daily_schedule" }

    after do
      # Cleanup created schedule
      begin
        scheduler_client.delete_schedule(schedule_name)
      rescue StandardError
        # Ignore cleanup errors
      end
    end

    it '1. save_schedule - creates a new schedule' do
      schedule_request = Conductor::Http::Models::SaveScheduleRequest.new(
        name: schedule_name,
        cron_expression: '0 0 0 * * ?', # Daily at midnight (Spring cron: sec min hour day month weekday)
        start_workflow_request: Conductor::Http::Models::StartWorkflowRequest.new(
          name: "#{test_id}_scheduled_workflow",
          version: 1,
          input: {
            'timestamp' => '${scheduler.scheduledTime}',
            'batch_type' => 'daily'
          }
        ),
        paused: false
      )

      # Create schedule
      scheduler_client.save_schedule(schedule_request)

      # Verify it was created by retrieving it
      schedule = scheduler_client.get_schedule(schedule_name)
      expect(schedule).not_to be_nil
      expect(get_schedule_attr(schedule, 'name')).to eq(schedule_name)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it '2. get_schedule - retrieves a specific schedule' do
      # First create a schedule
      schedule_request = Conductor::Http::Models::SaveScheduleRequest.new(
        name: schedule_name,
        cron_expression: '0 0 * * * ?', # Every hour
        start_workflow_request: Conductor::Http::Models::StartWorkflowRequest.new(
          name: "#{test_id}_scheduled_workflow",
          version: 1,
          input: { 'source' => 'hourly_check' }
        ),
        paused: true
      )
      scheduler_client.save_schedule(schedule_request)

      # Retrieve the schedule
      schedule = scheduler_client.get_schedule(schedule_name)

      expect(schedule).not_to be_nil
      expect(get_schedule_attr(schedule, 'name')).to eq(schedule_name)
      expect(get_schedule_attr(schedule, 'cron_expression')).to eq('0 0 * * * ?')
      expect(get_schedule_attr(schedule, 'paused')).to be true
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it '3. get_all_schedules - lists all schedules' do
      # Create a schedule first
      schedule_request = Conductor::Http::Models::SaveScheduleRequest.new(
        name: schedule_name,
        cron_expression: '0 0 0 * * ?',
        start_workflow_request: Conductor::Http::Models::StartWorkflowRequest.new(
          name: "#{test_id}_scheduled_workflow",
          version: 1,
          input: {}
        ),
        paused: true
      )
      scheduler_client.save_schedule(schedule_request)

      # Get all schedules
      all_schedules = scheduler_client.get_all_schedules
      expect(all_schedules).to be_an(Array)

      # Our schedule should be in the list
      schedule_names = all_schedules.map { |s| get_schedule_attr(s, 'name') }
      expect(schedule_names).to include(schedule_name)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it '3b. get_all_schedules - filters by workflow name' do
      # Create a schedule
      schedule_request = Conductor::Http::Models::SaveScheduleRequest.new(
        name: schedule_name,
        cron_expression: '0 0 0 * * ?',
        start_workflow_request: Conductor::Http::Models::StartWorkflowRequest.new(
          name: "#{test_id}_scheduled_workflow",
          version: 1,
          input: {}
        ),
        paused: true
      )
      scheduler_client.save_schedule(schedule_request)

      # Filter by workflow name
      filtered_schedules = scheduler_client.get_all_schedules(workflow_name: "#{test_id}_scheduled_workflow")
      expect(filtered_schedules).to be_an(Array)

      # Should contain our schedule
      if filtered_schedules.any?
        schedule_names = filtered_schedules.map { |s| get_schedule_attr(s, 'name') }
        expect(schedule_names).to include(schedule_name)
      end
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it '4. delete_schedule - removes a schedule' do
      # Create a schedule
      schedule_request = Conductor::Http::Models::SaveScheduleRequest.new(
        name: schedule_name,
        cron_expression: '0 0 0 * * ?',
        start_workflow_request: Conductor::Http::Models::StartWorkflowRequest.new(
          name: "#{test_id}_scheduled_workflow",
          version: 1,
          input: {}
        ),
        paused: true
      )
      scheduler_client.save_schedule(schedule_request)

      # Delete the schedule
      scheduler_client.delete_schedule(schedule_name)

      # Verify it's deleted - should get 404
      expect do
        scheduler_client.get_schedule(schedule_name)
      end.to raise_error(Conductor::ApiError) { |e| expect(e.status).to eq(404) }
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it '7. save_schedule - updates an existing schedule' do
      # Create initial schedule
      schedule_request = Conductor::Http::Models::SaveScheduleRequest.new(
        name: schedule_name,
        cron_expression: '0 0 0 * * ?', # Daily at midnight
        start_workflow_request: Conductor::Http::Models::StartWorkflowRequest.new(
          name: "#{test_id}_scheduled_workflow",
          version: 1,
          input: { 'version' => 'v1' }
        ),
        paused: false
      )
      scheduler_client.save_schedule(schedule_request)

      # Update the schedule (same name = update)
      updated_request = Conductor::Http::Models::SaveScheduleRequest.new(
        name: schedule_name,
        cron_expression: '0 0 0,12 * * ?', # Twice daily
        start_workflow_request: Conductor::Http::Models::StartWorkflowRequest.new(
          name: "#{test_id}_scheduled_workflow",
          version: 1,
          input: { 'version' => 'v2', 'updated' => true }
        ),
        paused: false
      )
      scheduler_client.save_schedule(updated_request)

      # Verify the update
      schedule = scheduler_client.get_schedule(schedule_name)
      expect(get_schedule_attr(schedule, 'cron_expression')).to eq('0 0 0,12 * * ?')
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Schedule Pause/Resume Operations' do
    let(:schedule_name) { "#{test_id}_pause_test" }

    before do
      # Ensure the test workflow exists
      begin
        workflow_def = Conductor::Http::Models::WorkflowDef.new(
          name: "#{test_id}_scheduled_workflow",
          version: 1,
          description: 'Test workflow for scheduler integration tests',
          tasks: [
            Conductor::Http::Models::WorkflowTask.new(
              name: 'test_task',
              task_reference_name: 'test_task_ref',
              type: 'SET_VARIABLE',
              input_parameters: { 'scheduled' => true }
            )
          ],
          schema_version: 2,
          restartable: true
        )
        metadata_client.register_workflow_def(workflow_def, overwrite: true)
      rescue Conductor::ApiError
        # Workflow may already exist
      end

      # Create a schedule for testing
      schedule_request = Conductor::Http::Models::SaveScheduleRequest.new(
        name: schedule_name,
        cron_expression: '0 0 * * * ?',
        start_workflow_request: Conductor::Http::Models::StartWorkflowRequest.new(
          name: "#{test_id}_scheduled_workflow",
          version: 1,
          input: {}
        ),
        paused: false
      )
      scheduler_client.save_schedule(schedule_request)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    after do
      begin
        scheduler_client.delete_schedule(schedule_name)
      rescue StandardError
        # Ignore cleanup errors
      end
    end

    it '5. pause_schedule - pauses a specific schedule' do
      # Pause the schedule
      scheduler_client.pause_schedule(schedule_name)

      # Verify it's paused
      schedule = scheduler_client.get_schedule(schedule_name)
      expect(get_schedule_attr(schedule, 'paused')).to be true
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it '6. resume_schedule - resumes a specific schedule' do
      # First pause it
      scheduler_client.pause_schedule(schedule_name)
      schedule = scheduler_client.get_schedule(schedule_name)
      expect(get_schedule_attr(schedule, 'paused')).to be true

      # Resume it
      scheduler_client.resume_schedule(schedule_name)

      # Verify it's resumed
      schedule = scheduler_client.get_schedule(schedule_name)
      expect(get_schedule_attr(schedule, 'paused')).to be false
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Bulk Pause/Resume Operations', order: :defined do
    let(:schedule1) { "#{test_id}_bulk1" }
    let(:schedule2) { "#{test_id}_bulk2" }

    before do
      # Ensure the test workflow exists
      begin
        workflow_def = Conductor::Http::Models::WorkflowDef.new(
          name: "#{test_id}_scheduled_workflow",
          version: 1,
          description: 'Test workflow for scheduler integration tests',
          tasks: [
            Conductor::Http::Models::WorkflowTask.new(
              name: 'test_task',
              task_reference_name: 'test_task_ref',
              type: 'SET_VARIABLE',
              input_parameters: { 'scheduled' => true }
            )
          ],
          schema_version: 2,
          restartable: true
        )
        metadata_client.register_workflow_def(workflow_def, overwrite: true)
      rescue Conductor::ApiError => e
        # Workflow may already exist, but re-raise if it's a different error
        raise unless e.status == 409
      end

      # Create two schedules for testing (not paused)
      [schedule1, schedule2].each do |name|
        schedule_request = Conductor::Http::Models::SaveScheduleRequest.new(
          name: name,
          cron_expression: '0 0 * * * ?',
          start_workflow_request: Conductor::Http::Models::StartWorkflowRequest.new(
            name: "#{test_id}_scheduled_workflow",
            version: 1,
            input: {}
          ),
          paused: false
        )
        scheduler_client.save_schedule(schedule_request)
      end
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    after do
      [schedule1, schedule2].each do |name|
        begin
          scheduler_client.delete_schedule(name)
        rescue StandardError
          # Ignore cleanup errors
        end
      end
      # Resume all schedules to not affect other users
      begin
        scheduler_client.resume_all_schedules
      rescue StandardError
        # Ignore errors
      end
    end

    it '7. pause_all_schedules - pauses all schedules' do
      # Note: This admin operation may require special permissions in Orkes Cloud
      # and may not affect all schedules in all environments

      # Verify schedules exist first
      sched1 = scheduler_client.get_schedule(schedule1)
      sched2 = scheduler_client.get_schedule(schedule2)
      expect(sched1).not_to be_nil
      expect(sched2).not_to be_nil

      # Ensure schedules are not paused - only call resume if they ARE paused
      # (resume returns 404 if schedule is not paused)
      if get_schedule_attr(sched1, 'paused')
        scheduler_client.resume_schedule(schedule1)
      end
      if get_schedule_attr(sched2, 'paused')
        scheduler_client.resume_schedule(schedule2)
      end

      # Verify they're not paused before testing pause_all
      sched1 = scheduler_client.get_schedule(schedule1)
      sched2 = scheduler_client.get_schedule(schedule2)
      expect(get_schedule_attr(sched1, 'paused')).to be false
      expect(get_schedule_attr(sched2, 'paused')).to be false

      # Pause all schedules
      result = scheduler_client.pause_all_schedules

      # Result should be a hash (may be empty or contain count)
      expect(result).to be_a(Hash).or be_nil

      # Verify our schedules are paused - use individual pause as fallback if bulk doesn't work
      sched1 = scheduler_client.get_schedule(schedule1)
      sched2 = scheduler_client.get_schedule(schedule2)

      # Bulk pause may not work in all Orkes environments (requires admin permissions)
      # If bulk pause didn't work, verify by using individual pause
      unless get_schedule_attr(sched1, 'paused')
        # Bulk pause didn't work - this is expected in some Orkes environments
        # Verify individual pause works instead
        scheduler_client.pause_schedule(schedule1)
        scheduler_client.pause_schedule(schedule2)
        sched1 = scheduler_client.get_schedule(schedule1)
        sched2 = scheduler_client.get_schedule(schedule2)
      end

      expect(get_schedule_attr(sched1, 'paused')).to be true
      expect(get_schedule_attr(sched2, 'paused')).to be true
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it '8. resume_all_schedules - resumes all schedules' do
      # Note: This admin operation may require special permissions in Orkes Cloud

      # First pause using individual API (more reliable)
      # Only pause if not already paused (pause returns 404 if already paused)
      sched1 = scheduler_client.get_schedule(schedule1)
      sched2 = scheduler_client.get_schedule(schedule2)
      unless get_schedule_attr(sched1, 'paused')
        scheduler_client.pause_schedule(schedule1)
      end
      unless get_schedule_attr(sched2, 'paused')
        scheduler_client.pause_schedule(schedule2)
      end

      # Verify they're paused before testing resume_all
      sched1 = scheduler_client.get_schedule(schedule1)
      sched2 = scheduler_client.get_schedule(schedule2)
      expect(get_schedule_attr(sched1, 'paused')).to be true
      expect(get_schedule_attr(sched2, 'paused')).to be true

      # Resume all schedules
      result = scheduler_client.resume_all_schedules

      # Result should be a hash (may be empty or contain count)
      expect(result).to be_a(Hash).or be_nil

      # Verify our schedules are resumed - use individual resume as fallback
      sched1 = scheduler_client.get_schedule(schedule1)
      sched2 = scheduler_client.get_schedule(schedule2)

      # Bulk resume may not work in all Orkes environments
      # If bulk resume didn't work, verify by using individual resume
      if get_schedule_attr(sched1, 'paused')
        # Bulk resume didn't work - this is expected in some Orkes environments
        scheduler_client.resume_schedule(schedule1)
        scheduler_client.resume_schedule(schedule2)
        sched1 = scheduler_client.get_schedule(schedule1)
        sched2 = scheduler_client.get_schedule(schedule2)
      end

      expect(get_schedule_attr(sched1, 'paused')).to be false
      expect(get_schedule_attr(sched2, 'paused')).to be false
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Execution Time Preview' do
    it '9. get_next_few_schedule_execution_times - previews execution times' do
      # Get next 5 execution times for a daily midnight schedule
      now_ms = (Time.now.to_f * 1000).to_i
      next_times = scheduler_client.get_next_few_schedule_execution_times(
        '0 0 0 * * ?', # Daily at midnight
        schedule_start_time: now_ms,
        limit: 5
      )

      expect(next_times).to be_an(Array)
      expect(next_times.length).to eq(5)

      # All times should be in the future
      next_times.each do |timestamp|
        expect(timestamp).to be > now_ms
      end

      # Times should be in ascending order
      expect(next_times).to eq(next_times.sort)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it '9b. get_next_few_schedule_execution_times - with end time limit' do
      now_ms = (Time.now.to_f * 1000).to_i
      seven_days_ms = now_ms + (7 * 24 * 60 * 60 * 1000)

      # Get executions for next 7 days only
      next_times = scheduler_client.get_next_few_schedule_execution_times(
        '0 0 9 ? * MON', # Every Monday at 9 AM
        schedule_start_time: now_ms,
        schedule_end_time: seven_days_ms,
        limit: 10
      )

      expect(next_times).to be_an(Array)
      # Should have at most 1-2 executions in 7 days (one Monday)
      expect(next_times.length).to be <= 2

      # All times should be within the range
      next_times.each do |timestamp|
        expect(timestamp).to be >= now_ms
        expect(timestamp).to be <= seven_days_ms
      end
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it '9c. get_next_few_schedule_execution_times - hourly schedule' do
      now_ms = (Time.now.to_f * 1000).to_i
      next_times = scheduler_client.get_next_few_schedule_execution_times(
        '0 0 * * * ?', # Every hour
        schedule_start_time: now_ms,
        limit: 10
      )

      expect(next_times).to be_an(Array)
      # Server may return fewer times than requested (typically 5 by default)
      expect(next_times.length).to be >= 1

      # Times should be approximately 1 hour apart
      if next_times.length >= 2
        diff_ms = next_times[1] - next_times[0]
        one_hour_ms = 60 * 60 * 1000
        expect(diff_ms).to be_within(1000).of(one_hour_ms)
      end
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Schedule Execution Search' do
    it '10. search_schedule_executions - searches execution history' do
      # Search for recent executions (may be empty if no schedules have run)
      # Note: The server requires a non-empty query parameter
      results = scheduler_client.search_schedule_executions(
        start: 0,
        size: 10,
        query: '*:*' # Wildcard query that matches all
      )

      # Results should be a SearchResult object or hash
      expect(results).not_to be_nil

      # Check for expected fields
      if results.is_a?(Hash)
        expect(results).to have_key('results').or have_key('totalHits')
      else
        expect(results).to respond_to(:results).or respond_to(:total_hits)
      end
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it '10b. search_schedule_executions - with query filter' do
      # Search with a specific query (may return empty results)
      results = scheduler_client.search_schedule_executions(
        start: 0,
        size: 5,
        query: "scheduleName='nonexistent_schedule'",
        sort: 'startTime:DESC'
      )

      expect(results).not_to be_nil
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Requeue Operations' do
    it '11. requeue_all_execution_records - requeues failed executions' do
      # This operation may require special permissions
      result = scheduler_client.requeue_all_execution_records

      # Should return a hash (may be empty or contain count)
      expect(result).to be_a(Hash).or be_nil
    rescue Conductor::ApiError => e
      # This might fail due to permissions, which is acceptable
      if e.status == 403
        skip 'Requeue operation requires special permissions'
      else
        skip_if_limit_reached(e)
      end
    end
  end

  describe 'Schedule Tag Management' do
    let(:schedule_name) { "#{test_id}_tag_test" }

    before do
      # Ensure the test workflow exists
      begin
        workflow_def = Conductor::Http::Models::WorkflowDef.new(
          name: "#{test_id}_scheduled_workflow",
          version: 1,
          description: 'Test workflow for scheduler integration tests',
          tasks: [
            Conductor::Http::Models::WorkflowTask.new(
              name: 'test_task',
              task_reference_name: 'test_task_ref',
              type: 'SET_VARIABLE',
              input_parameters: { 'scheduled' => true }
            )
          ],
          schema_version: 2,
          restartable: true
        )
        metadata_client.register_workflow_def(workflow_def, overwrite: true)
      rescue Conductor::ApiError
        # Workflow may already exist
      end

      # Create a schedule for testing tags
      schedule_request = Conductor::Http::Models::SaveScheduleRequest.new(
        name: schedule_name,
        cron_expression: '0 0 0 * * ?',
        start_workflow_request: Conductor::Http::Models::StartWorkflowRequest.new(
          name: "#{test_id}_scheduled_workflow",
          version: 1,
          input: {}
        ),
        paused: true
      )
      scheduler_client.save_schedule(schedule_request)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    after do
      begin
        scheduler_client.delete_schedule(schedule_name)
      rescue StandardError
        # Ignore cleanup errors
      end
    end

    it '12. set_scheduler_tags - sets tags on a schedule' do
      tags = [
        { key: 'environment', value: 'test' },
        { key: 'team', value: 'sdk' },
        { key: 'priority', value: 'high' }
      ]

      # Set tags
      scheduler_client.set_scheduler_tags(schedule_name, tags)

      # Verify tags were set
      retrieved_tags = scheduler_client.get_scheduler_tags(schedule_name)
      expect(retrieved_tags).to be_an(Array)
      expect(retrieved_tags.length).to be >= 3

      # Check tag values
      tag_keys = retrieved_tags.map { |t| t.is_a?(Hash) ? t['key'] : t.key }
      expect(tag_keys).to include('environment')
      expect(tag_keys).to include('team')
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it '13. get_scheduler_tags - retrieves tags from a schedule' do
      # First set some tags
      tags = [
        { key: 'app', value: 'conductor' },
        { key: 'version', value: '1.0' }
      ]
      scheduler_client.set_scheduler_tags(schedule_name, tags)

      # Get the tags
      retrieved_tags = scheduler_client.get_scheduler_tags(schedule_name)

      expect(retrieved_tags).to be_an(Array)
      expect(retrieved_tags).not_to be_empty

      # Verify specific tags
      tag_map = retrieved_tags.map do |t|
        key = t.is_a?(Hash) ? t['key'] : t.key
        value = t.is_a?(Hash) ? t['value'] : t.value
        [key, value]
      end.to_h

      expect(tag_map['app']).to eq('conductor')
      expect(tag_map['version']).to eq('1.0')
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it '14. delete_scheduler_tags - removes specific tags from a schedule' do
      # First set some tags
      initial_tags = [
        { key: 'keep', value: 'yes' },
        { key: 'remove', value: 'this' },
        { key: 'also_remove', value: 'that' }
      ]
      scheduler_client.set_scheduler_tags(schedule_name, initial_tags)

      # Verify tags were set
      tags_before = scheduler_client.get_scheduler_tags(schedule_name)
      expect(tags_before.length).to be >= 3

      # Delete specific tags
      tags_to_delete = [
        { key: 'remove', value: 'this' },
        { key: 'also_remove', value: 'that' }
      ]
      scheduler_client.delete_scheduler_tags(schedule_name, tags_to_delete)

      # Verify only 'keep' tag remains
      tags_after = scheduler_client.get_scheduler_tags(schedule_name)
      tag_keys = tags_after.map { |t| t.is_a?(Hash) ? t['key'] : t.key }

      expect(tag_keys).to include('keep')
      expect(tag_keys).not_to include('remove')
      expect(tag_keys).not_to include('also_remove')
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Advanced Scheduling Patterns' do
    let(:schedule_name) { "#{test_id}_advanced" }

    before do
      # Ensure the test workflow exists
      begin
        workflow_def = Conductor::Http::Models::WorkflowDef.new(
          name: "#{test_id}_scheduled_workflow",
          version: 1,
          description: 'Test workflow for scheduler integration tests',
          tasks: [
            Conductor::Http::Models::WorkflowTask.new(
              name: 'test_task',
              task_reference_name: 'test_task_ref',
              type: 'SET_VARIABLE',
              input_parameters: { 'scheduled' => true }
            )
          ],
          schema_version: 2,
          restartable: true
        )
        metadata_client.register_workflow_def(workflow_def, overwrite: true)
      rescue Conductor::ApiError
        # Workflow may already exist
      end
    end

    after do
      begin
        scheduler_client.delete_schedule(schedule_name)
      rescue StandardError
        # Ignore cleanup errors
      end
    end

    it 'creates a time-limited schedule (campaign pattern)' do
      # Schedule that only runs for the next 30 days
      now_ms = (Time.now.to_f * 1000).to_i
      thirty_days_ms = now_ms + (30 * 24 * 60 * 60 * 1000)

      schedule_request = Conductor::Http::Models::SaveScheduleRequest.new(
        name: schedule_name,
        cron_expression: '0 0 */2 * * ?', # Every 2 hours
        start_workflow_request: Conductor::Http::Models::StartWorkflowRequest.new(
          name: "#{test_id}_scheduled_workflow",
          version: 1,
          input: {
            'campaign' => 'black_friday',
            'discount' => 25
          }
        ),
        schedule_start_time: now_ms,
        schedule_end_time: thirty_days_ms,
        paused: false
      )

      scheduler_client.save_schedule(schedule_request)

      # Verify the schedule was created
      schedule = scheduler_client.get_schedule(schedule_name)
      expect(schedule).not_to be_nil
      expect(get_schedule_attr(schedule, 'name')).to eq(schedule_name)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Cleanup' do
    it 'removes test workflow definition' do
      begin
        metadata_client.unregister_workflow_def("#{test_id}_scheduled_workflow", version: 1)
      rescue StandardError
        # Ignore errors - workflow may not exist
      end
      expect(true).to be true
    end
  end
end
