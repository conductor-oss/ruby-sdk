# frozen_string_literal: true

require 'timeout'
require_relative '../errors'
require_relative 'approval_request'

module Conductor
  module Agents
    # Token usage for an execution (summed over sub-agent executions)
    TokenUsage = Struct.new(:prompt_tokens, :completion_tokens, :total_tokens, keyword_init: true) do
      def initialize(prompt_tokens: 0, completion_tokens: 0, total_tokens: 0)
        super
      end

      def +(other)
        TokenUsage.new(prompt_tokens: prompt_tokens + other.prompt_tokens,
                       completion_tokens: completion_tokens + other.completion_tokens,
                       total_tokens: total_tokens + other.total_tokens)
      end
    end

    # Maps the server's status + output.finishReason to a Symbol
    module FinishReason
      def self.derive(status, output)
        case status.to_s
        when 'COMPLETED'
          fr = output.is_a?(Hash) ? output['finishReason'].to_s : ''
          case fr
          when 'rejected' then :rejected
          when 'LENGTH', 'MAX_TOKENS' then :length
          when 'tool_calls', 'TOOL_CALLS' then :tool_calls
          when 'CONTENT_FILTER' then :content_filter
          else :stop
          end
        when 'FAILED' then :error
        when 'TERMINATED' then :cancelled
        when 'TIMED_OUT' then :timeout
        else :stop
        end
      end
    end

    # Handle on a running (or finished) agent execution.
    #
    #   execution = agent.call_async('Refund order A-1029')
    #   execution.done?          # false until finished
    #   execution.partial_text   # streamed text so far
    #   execution.result         # blocks for the answer
    #   execution.finish_reason  # :stop | :rejected | ...
    class Execution
      TERMINAL_STATUSES = %w[COMPLETED FAILED TERMINATED TIMED_OUT].freeze

      attr_reader :execution_id, :agent_name, :tool_calls, :token_usage, :pending, :error, :status, :output, :events

      # @param execution_id [String] also the Conductor workflow id
      # @param client [Client::AgentClient]
      def initialize(execution_id, client:, agent_name: nil, runtime: nil)
        @execution_id = execution_id
        @client = client
        @agent_name = agent_name
        @runtime = runtime
        @mutex = Mutex.new
        @done_cv = ConditionVariable.new
        @partial_text = +''
        @tool_calls = []
        @events = []
        @token_usage = TokenUsage.new
        @pending = nil
        @status = 'RUNNING'
        @output = nil
        @result = nil
        @error = nil
        @waiting = false
        @finished = false
      end

      # Look up an execution by id (a snapshot; +result+ attaches a stream if still running)
      # @return [Execution]
      def self.find(execution_id, runtime: Conductor::Agents.runtime)
        execution = new(execution_id, client: runtime.client, runtime: runtime)
        execution.refresh!
        execution
      end

      # Re-read status from the server
      def refresh!
        status = @client.get_status(@execution_id)
        @agent_name ||= status['agentName']
        if status['isComplete']
          finish(status: status['status'], output: status['output'], reason: status['reasonForIncompletion'])
        elsif status['isWaiting']
          mark_waiting(ApprovalRequest.new(@execution_id, status['pendingTool'], client: @client, execution: self))
        else
          clear_waiting
        end
        self
      end

      def done?
        @mutex.synchronize { @finished }
      end

      def waiting?
        @mutex.synchronize { @waiting && !@finished }
      end

      # Text streamed so far (never behind +result+ once done)
      def partial_text
        @mutex.synchronize { @partial_text.dup }
      end

      # Block until finished and return the answer
      # @param timeout [Numeric, nil] seconds; nil waits forever
      # @raise [Error] when the execution failed, was cancelled or timed out on the server
      # @raise [Timeout::Error] when +timeout+ elapses first
      def result(timeout: nil)
        @runtime&.attach(self) unless done? || @attached
        @mutex.synchronize do
          deadline = timeout && (Time.now + timeout)
          until @finished
            remaining = deadline && (deadline - Time.now)
            raise Timeout::Error, "execution #{@execution_id} still running after #{timeout}s" if remaining && remaining <= 0

            @done_cv.wait(@mutex, remaining)
          end
          raise Error, "execution #{@execution_id} #{@status.downcase}: #{@error}" if @error && @status != 'COMPLETED'

          @result
        end
      end

      # The answer without blocking or raising (nil while running or when failed)
      def answer
        @mutex.synchronize { @finished ? @result : nil }
      end

      # @return [Symbol] :stop | :tool_calls | :length | :content_filter | :rejected | :error | :cancelled | :timeout | nil
      def finish_reason
        @mutex.synchronize { @finished ? FinishReason.derive(@status, @output) : nil }
      end

      def rejected?
        finish_reason == :rejected
      end

      # ── control ─────────────────────────────────────────────────────

      def pause
        @client.pause(@execution_id)
        self
      end

      def resume
        @client.resume(@execution_id)
        self
      end

      def cancel(reason: 'cancelled by client')
        @client.cancel(@execution_id, reason: reason)
        self
      end

      def stop
        @client.stop(@execution_id)
        self
      end

      def signal(message)
        @client.signal(@execution_id, message)
        self
      end

      # Approve / reject the pending tool call, if any
      def approve
        (pending || raise(Error, 'nothing is waiting for approval')).approve
      end

      def reject(reason = '')
        (pending || raise(Error, 'nothing is waiting for approval')).reject(reason)
      end

      # ── mutators used by the runtime's stream thread ────────────────

      def attached!
        @attached = true
      end

      def record_event(event)
        @mutex.synchronize { @events << event }
      end

      def append_text(text)
        return if text.nil? || text.to_s.empty?

        @mutex.synchronize { @partial_text << text.to_s }
      end

      def add_tool_call(name, arguments)
        @mutex.synchronize { @tool_calls << ToolCall.new(name: name, arguments: arguments || {}) }
      end

      def add_tool_result(name, result)
        @mutex.synchronize do
          call = @tool_calls.reverse.find { |c| c.name == name && c.result.nil? }
          call ? call.result = result : @tool_calls << ToolCall.new(name: name, arguments: {}, result: result)
        end
      end

      def mark_waiting(pending)
        @mutex.synchronize do
          @waiting = true
          @pending = pending
        end
      end

      def clear_waiting
        @mutex.synchronize do
          @waiting = false
          @pending = nil
        end
      end

      def token_usage=(usage)
        @mutex.synchronize { @token_usage = usage }
      end

      # Mark the execution finished. +output+ is the workflow output ({result, finishReason, ...}).
      def finish(status:, output:, reason: nil)
        @mutex.synchronize do
          return if @finished

          @status = status.to_s
          @output = output.is_a?(Hash) ? output : {}
          @result = extract_result(output)
          @error = reason if reason && !reason.to_s.empty?
          @error ||= (@output['error'] || @output['reason']) unless @status == 'COMPLETED'
          @error ||= "execution #{@status.downcase}" unless @status == 'COMPLETED'
          @partial_text = @result.to_s.dup if @result.is_a?(String) && @partial_text.empty?
          @waiting = false
          @pending = nil
          @finished = true
          @done_cv.broadcast
        end
      end

      def fail(reason)
        finish(status: 'FAILED', output: { 'error' => reason }, reason: reason)
      end

      def to_s
        "#<Conductor::Agents::Execution #{@execution_id} #{@status}#{@finished ? '' : ' (running)'}>"
      end
      alias inspect to_s

      private

      def extract_result(output)
        return output unless output.is_a?(Hash)
        return output['result'] if output.key?('result')

        output
      end
    end
  end
end
