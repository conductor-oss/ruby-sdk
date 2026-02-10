# frozen_string_literal: true

require_relative 'integration_helper'

RSpec.describe 'Metadata API Integration', :integration do
  let(:metadata_client) { IntegrationHelper.metadata_client }

  # ==========================================
  # Task Definition CRUD
  # ==========================================
  describe 'Task Definition Operations' do
    let(:task_name) { IntegrationHelper.test_name('simple_task') }

    after do
      IntegrationHelper.cleanup_task_def(task_name)
    end

    it 'registers a task definition' do
      task_def = Conductor::Http::Models::TaskDef.new
      task_def.name = task_name
      task_def.description = 'Integration test task'
      task_def.retry_count = 3
      task_def.retry_logic = Conductor::Http::Models::RetryLogic::FIXED
      task_def.timeout_policy = Conductor::Http::Models::TaskTimeoutPolicy::TIME_OUT_WF
      task_def.timeout_seconds = 60
      task_def.response_timeout_seconds = 30

      expect { metadata_client.register_task_def(task_def) }.not_to raise_error
    end

    it 'retrieves a registered task definition' do
      # Register first
      task_def = Conductor::Http::Models::TaskDef.new
      task_def.name = task_name
      task_def.description = 'Integration test task'
      task_def.retry_count = 2
      task_def.timeout_seconds = 45
      task_def.response_timeout_seconds = 30
      metadata_client.register_task_def(task_def)

      # Retrieve
      retrieved = metadata_client.get_task_def(task_name)
      expect(retrieved).to be_a(Conductor::Http::Models::TaskDef)
      expect(retrieved.name).to eq(task_name)
      expect(retrieved.retry_count).to eq(2)
      expect(retrieved.timeout_seconds).to eq(45)
    end

    it 'retrieves all task definitions' do
      # Register a task first
      task_def = Conductor::Http::Models::TaskDef.new
      task_def.name = task_name
      task_def.timeout_seconds = 60
      task_def.response_timeout_seconds = 30
      metadata_client.register_task_def(task_def)

      # Get all
      all_defs = metadata_client.get_all_task_defs
      expect(all_defs).to be_an(Array)
      expect(all_defs.length).to be > 0

      # Find our test task
      our_task = all_defs.find { |td| td.name == task_name }
      expect(our_task).not_to be_nil
    end

    it 'updates a task definition' do
      # Register first
      task_def = Conductor::Http::Models::TaskDef.new
      task_def.name = task_name
      task_def.description = 'Original description'
      task_def.retry_count = 1
      task_def.timeout_seconds = 30
      task_def.response_timeout_seconds = 30
      metadata_client.register_task_def(task_def)

      # Update
      task_def.description = 'Updated description'
      task_def.retry_count = 5
      task_def.timeout_seconds = 120
      metadata_client.update_task_def(task_def)

      # Verify update
      updated = metadata_client.get_task_def(task_name)
      expect(updated.retry_count).to eq(5)
      expect(updated.timeout_seconds).to eq(120)
    end

    it 'unregisters (deletes) a task definition' do
      # Register first
      task_def = Conductor::Http::Models::TaskDef.new
      task_def.name = task_name
      task_def.timeout_seconds = 60
      task_def.response_timeout_seconds = 30
      metadata_client.register_task_def(task_def)

      # Verify it exists
      retrieved = metadata_client.get_task_def(task_name)
      expect(retrieved.name).to eq(task_name)

      # Delete
      expect { metadata_client.unregister_task_def(task_name) }.not_to raise_error

      # Verify it's gone (should raise an error)
      expect { metadata_client.get_task_def(task_name) }.to raise_error(Conductor::ApiError)
    end

    it 'registers multiple task definitions at once' do
      task_name_2 = "#{task_name}_2"

      task_def_1 = Conductor::Http::Models::TaskDef.new
      task_def_1.name = task_name
      task_def_1.timeout_seconds = 30
      task_def_1.response_timeout_seconds = 30

      task_def_2 = Conductor::Http::Models::TaskDef.new
      task_def_2.name = task_name_2
      task_def_2.timeout_seconds = 60
      task_def_2.response_timeout_seconds = 30

      expect { metadata_client.register_task_defs([task_def_1, task_def_2]) }.not_to raise_error

      # Verify both exist
      expect(metadata_client.get_task_def(task_name).name).to eq(task_name)
      expect(metadata_client.get_task_def(task_name_2).name).to eq(task_name_2)

      # Cleanup extra
      IntegrationHelper.cleanup_task_def(task_name_2)
    end
  end

  # ==========================================
  # Workflow Definition CRUD
  # ==========================================
  describe 'Workflow Definition Operations' do
    let(:workflow_name) { IntegrationHelper.test_name('test_workflow') }
    let(:task_name) { IntegrationHelper.test_name('wf_task') }

    before do
      # Register a task definition for the workflow to use
      task_def = Conductor::Http::Models::TaskDef.new
      task_def.name = task_name
      task_def.timeout_seconds = 60
      task_def.response_timeout_seconds = 30
      metadata_client.register_task_def(task_def)
    end

    after do
      IntegrationHelper.cleanup_workflow_def(workflow_name, version: 1)
      IntegrationHelper.cleanup_workflow_def(workflow_name, version: 2)
      IntegrationHelper.cleanup_task_def(task_name)
    end

    it 'registers a workflow definition' do
      workflow_def = build_simple_workflow(workflow_name, task_name)
      expect { metadata_client.register_workflow_def(workflow_def) }.not_to raise_error
    end

    it 'retrieves a registered workflow definition' do
      workflow_def = build_simple_workflow(workflow_name, task_name)
      metadata_client.register_workflow_def(workflow_def)

      retrieved = metadata_client.get_workflow_def(workflow_name)
      expect(retrieved).to be_a(Conductor::Http::Models::WorkflowDef)
      expect(retrieved.name).to eq(workflow_name)
      expect(retrieved.version).to eq(1)
      expect(retrieved.tasks).to be_an(Array)
      expect(retrieved.tasks.length).to eq(1)
    end

    it 'retrieves all workflow definitions' do
      workflow_def = build_simple_workflow(workflow_name, task_name)
      metadata_client.register_workflow_def(workflow_def)

      all_defs = metadata_client.get_all_workflow_defs
      expect(all_defs).to be_an(Array)
      expect(all_defs.length).to be > 0

      our_wf = all_defs.find { |wd| wd.name == workflow_name }
      expect(our_wf).not_to be_nil
    end

    it 'updates a workflow definition' do
      workflow_def = build_simple_workflow(workflow_name, task_name)
      metadata_client.register_workflow_def(workflow_def)

      # Update with new timeout
      workflow_def.timeout_seconds = 600
      metadata_client.update_workflow_def(workflow_def)

      # Verify
      updated = metadata_client.get_workflow_def(workflow_name)
      expect(updated.timeout_seconds).to eq(600)
    end

    it 'creates a version 2 of a workflow' do
      # Register version 1
      wf_v1 = build_simple_workflow(workflow_name, task_name)
      metadata_client.register_workflow_def(wf_v1)

      # Register version 2
      wf_v2 = build_simple_workflow(workflow_name, task_name, version: 2)
      metadata_client.register_workflow_def(wf_v2)

      # Retrieve specific version
      v1 = metadata_client.get_workflow_def(workflow_name, version: 1)
      expect(v1.version).to eq(1)

      v2 = metadata_client.get_workflow_def(workflow_name, version: 2)
      expect(v2.version).to eq(2)
    end

    it 'unregisters (deletes) a workflow definition' do
      workflow_def = build_simple_workflow(workflow_name, task_name)
      metadata_client.register_workflow_def(workflow_def)

      # Verify exists
      retrieved = metadata_client.get_workflow_def(workflow_name)
      expect(retrieved.name).to eq(workflow_name)

      # Delete
      expect { metadata_client.unregister_workflow_def(workflow_name, version: 1) }.not_to raise_error

      # Verify gone
      expect { metadata_client.get_workflow_def(workflow_name, version: 1) }.to raise_error(Conductor::ApiError)
    end
  end

  private

  # Build a simple workflow definition for testing
  def build_simple_workflow(name, task_name, version: 1)
    task = Conductor::Http::Models::WorkflowTask.new
    task.name = task_name
    task.task_reference_name = "#{task_name}_ref"
    task.type = 'SIMPLE'
    task.input_parameters = { 'input' => '${workflow.input.value}' }

    workflow_def = Conductor::Http::Models::WorkflowDef.new
    workflow_def.name = name
    workflow_def.version = version
    workflow_def.description = "Integration test workflow v#{version}"
    workflow_def.tasks = [task]
    workflow_def.schema_version = 2
    workflow_def.timeout_seconds = 300
    workflow_def.timeout_policy = 'TIME_OUT_WF'
    workflow_def.owner_email = 'test@example.com'
    workflow_def
  end
end
