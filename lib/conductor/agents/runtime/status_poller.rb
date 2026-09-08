# frozen_string_literal: true

module Conductor
  module Agents
    # Polling fallback for servers without SSE: turns GET /agent/{id}/status into the
    # same event hashes the SseClient yields (waiting, done, error). No partial text.
    class StatusPoller
      def initialize(client, interval: 0.5, logger: nil)
        @client = client
        @interval = interval
        @logger = logger
      end

      def each_event(execution_id)
        return enum_for(:each_event, execution_id) unless block_given?

        was_waiting = false
        loop do
          status = @client.get_status(execution_id)
          if status['isComplete']
            yield terminal_event(status)
            return
          end

          if status['isWaiting'] && !was_waiting
            yield({ 'event' => 'waiting', 'id' => nil, 'data' => { 'type' => 'waiting', 'executionId' => execution_id,
                                                                   'pendingTool' => status['pendingTool'] || {} } })
          end
          was_waiting = status['isWaiting'] ? true : false
          sleep(was_waiting ? [@interval * 4, 2.0].min : @interval)
        end
      end

      private

      def terminal_event(status)
        if status['status'].to_s == 'COMPLETED'
          { 'event' => 'done', 'id' => nil,
            'data' => { 'type' => 'done', 'executionId' => status['executionId'], 'output' => status['output'] || {} } }
        else
          { 'event' => 'error', 'id' => nil,
            'data' => { 'type' => 'error', 'executionId' => status['executionId'], 'status' => status['status'],
                        'content' => status['reasonForIncompletion'] || "execution #{status['status']}",
                        'output' => status['output'] } }
        end
      end
    end
  end
end
