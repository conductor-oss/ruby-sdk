# frozen_string_literal: true

require_relative '../errors'
require_relative '../../worker/task_context'

module Conductor
  module Agents
    # Read secrets inside a tool body.
    #
    #   tool def create_issue(title: String)
    #     Github.create_issue(title, token: secret('GH_TOKEN'))
    #   end
    #
    # The literal name is also the declaration: the Tools DSL scans the body and puts
    # GH_TOKEN on the tool's TaskDef#runtime_metadata. The server resolves it from its
    # secret store at poll time and delivers the value on Task#runtime_metadata, which
    # TaskContext (thread/fiber-local) exposes to the running tool. Nothing is ever written
    # to ENV; for subprocesses use secrets_env.
    module Secrets
      module_function

      # @param name [String, Symbol]
      # @return [String]
      # @raise [CredentialNotFoundError] when neither the task nor ENV has it
      def secret(name)
        key = name.to_s
        value = task_secrets[key]
        value = ENV.fetch(key, nil) if value.nil?
        return value unless value.nil?

        raise CredentialNotFoundError,
              "secret #{key.inspect} not found: it was not delivered on the task's runtimeMetadata " \
              "and ENV[#{key.inspect}] is unset. Store it on the server (conductor secrets put #{key} ...) " \
              'or declare it with add_tool ..., credentials: [...]'
      end

      # Environment hash for system / spawn / Open3: { 'GH_TOKEN' => '...' }
      # @return [Hash<String, String>]
      def secrets_env(*names)
        names.flatten.each_with_object({}) { |n, env| env[n.to_s] = secret(n) }
      end

      # Secrets bound for the current task (wire-only Task#runtime_metadata)
      # @return [Hash<String, String>]
      def task_secrets
        ctx = Conductor::Worker::TaskContext.current
        task = ctx&.task
        return {} unless task.respond_to?(:runtime_metadata)

        task.runtime_metadata || {}
      end
    end
  end
end
