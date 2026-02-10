# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # Represents a workflow task definition within a workflow
      # Used for serialization to/from JSON when registering workflows
      class WorkflowTask < BaseModel
        SWAGGER_TYPES = {
          name: 'String',
          task_reference_name: 'String',
          type: 'String',
          description: 'String',
          optional: 'Boolean',
          input_parameters: 'Hash<String, Object>',
          dynamic_task_name_param: 'String',
          case_value_param: 'String',
          case_expression: 'String',
          script_expression: 'String',
          decision_cases: 'Hash<String, Array<WorkflowTask>>',
          dynamic_fork_join_tasks_param: 'String',
          dynamic_fork_tasks_param: 'String',
          dynamic_fork_tasks_input_param_name: 'String',
          default_case: 'Array<WorkflowTask>',
          fork_tasks: 'Array<Array<WorkflowTask>>',
          start_delay: 'Integer',
          sub_workflow_param: 'SubWorkflowParams',
          join_on: 'Array<String>',
          sink: 'String',
          task_definition: 'Object',
          rate_limited: 'Boolean',
          default_exclusive_join_task: 'Array<String>',
          async_complete: 'Boolean',
          loop_condition: 'String',
          loop_over: 'Array<WorkflowTask>',
          retry_count: 'Integer',
          evaluator_type: 'String',
          expression: 'String',
          workflow_task_type: 'String',
          cache_config: 'CacheConfig'
        }.freeze

        ATTRIBUTE_MAP = {
          name: :name,
          task_reference_name: :taskReferenceName,
          type: :type,
          description: :description,
          optional: :optional,
          input_parameters: :inputParameters,
          dynamic_task_name_param: :dynamicTaskNameParam,
          case_value_param: :caseValueParam,
          case_expression: :caseExpression,
          script_expression: :scriptExpression,
          decision_cases: :decisionCases,
          dynamic_fork_join_tasks_param: :dynamicForkJoinTasksParam,
          dynamic_fork_tasks_param: :dynamicForkTasksParam,
          dynamic_fork_tasks_input_param_name: :dynamicForkTasksInputParamName,
          default_case: :defaultCase,
          fork_tasks: :forkTasks,
          start_delay: :startDelay,
          sub_workflow_param: :subWorkflowParam,
          join_on: :joinOn,
          sink: :sink,
          task_definition: :taskDefinition,
          rate_limited: :rateLimited,
          default_exclusive_join_task: :defaultExclusiveJoinTask,
          async_complete: :asyncComplete,
          loop_condition: :loopCondition,
          loop_over: :loopOver,
          retry_count: :retryCount,
          evaluator_type: :evaluatorType,
          expression: :expression,
          workflow_task_type: :workflowTaskType,
          cache_config: :cacheConfig
        }.freeze

        attr_accessor :name, :task_reference_name, :type, :description, :optional,
                      :input_parameters, :dynamic_task_name_param, :case_value_param,
                      :case_expression, :script_expression, :decision_cases,
                      :dynamic_fork_join_tasks_param, :dynamic_fork_tasks_param,
                      :dynamic_fork_tasks_input_param_name, :default_case, :fork_tasks,
                      :start_delay, :sub_workflow_param, :join_on, :sink,
                      :task_definition, :rate_limited, :default_exclusive_join_task,
                      :async_complete, :loop_condition, :loop_over, :retry_count,
                      :evaluator_type, :expression, :workflow_task_type, :cache_config

        def initialize(params = {})
          @name = params[:name]
          @task_reference_name = params[:task_reference_name]
          @type = params[:type]
          @description = params[:description]
          @optional = params[:optional]
          @input_parameters = params[:input_parameters] || {}
          @dynamic_task_name_param = params[:dynamic_task_name_param]
          @case_value_param = params[:case_value_param]
          @case_expression = params[:case_expression]
          @script_expression = params[:script_expression]
          @decision_cases = params[:decision_cases]
          @dynamic_fork_join_tasks_param = params[:dynamic_fork_join_tasks_param]
          @dynamic_fork_tasks_param = params[:dynamic_fork_tasks_param]
          @dynamic_fork_tasks_input_param_name = params[:dynamic_fork_tasks_input_param_name]
          @default_case = params[:default_case]
          @fork_tasks = params[:fork_tasks]
          @start_delay = params[:start_delay]
          @sub_workflow_param = params[:sub_workflow_param]
          @join_on = params[:join_on]
          @sink = params[:sink]
          @task_definition = params[:task_definition]
          @rate_limited = params[:rate_limited]
          @default_exclusive_join_task = params[:default_exclusive_join_task]
          @async_complete = params[:async_complete]
          @loop_condition = params[:loop_condition]
          @loop_over = params[:loop_over]
          @retry_count = params[:retry_count]
          @evaluator_type = params[:evaluator_type]
          @expression = params[:expression]
          @workflow_task_type = params[:workflow_task_type]
          @cache_config = params[:cache_config]
        end
      end

      # Cache configuration for tasks
      class CacheConfig < BaseModel
        SWAGGER_TYPES = {
          key: 'String',
          ttl_in_second: 'Integer'
        }.freeze

        ATTRIBUTE_MAP = {
          key: :key,
          ttl_in_second: :ttlInSecond
        }.freeze

        attr_accessor :key, :ttl_in_second

        def initialize(params = {})
          @key = params[:key]
          @ttl_in_second = params[:ttl_in_second]
        end
      end

      # Sub-workflow parameters for SUB_WORKFLOW tasks
      class SubWorkflowParams < BaseModel
        SWAGGER_TYPES = {
          name: 'String',
          version: 'Integer',
          task_to_domain: 'Hash<String, String>',
          workflow_definition: 'WorkflowDef'
        }.freeze

        ATTRIBUTE_MAP = {
          name: :name,
          version: :version,
          task_to_domain: :taskToDomain,
          workflow_definition: :workflowDefinition
        }.freeze

        attr_accessor :name, :version, :task_to_domain, :workflow_definition

        def initialize(params = {})
          @name = params[:name]
          @version = params[:version]
          @task_to_domain = params[:task_to_domain]
          @workflow_definition = params[:workflow_definition]
        end
      end
    end
  end
end
