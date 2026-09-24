# frozen_string_literal: true

module Conductor
  module Agents
    # Lifecycle hooks. Subclass and override any method; each runs as a worker task
    # named <agent>_<position> that the server schedules at that point.
    #
    #   class Timing < Conductor::Agents::CallbackHandler
    #     def on_model_start(messages: nil, **) = (@t0 = Time.now; nil)
    #     def on_model_end(llm_result: nil, **) = (puts Time.now - @t0; nil)
    #   end
    #
    # Return nil to continue to the next handler, or a non-empty Hash to short-circuit and
    # hand that Hash to the server as an override.
    class CallbackHandler
      POSITION_TO_METHOD = {
        'before_agent' => :on_agent_start,
        'after_agent' => :on_agent_end,
        'before_model' => :on_model_start,
        'after_model' => :on_model_end,
        'before_tool' => :on_tool_start,
        'after_tool' => :on_tool_end
      }.freeze

      POSITIONS = POSITION_TO_METHOD.keys.freeze

      def on_agent_start(**_kwargs); end
      def on_agent_end(**_kwargs); end
      def on_model_start(**_kwargs); end
      def on_model_end(**_kwargs); end
      def on_tool_start(**_kwargs); end
      def on_tool_end(**_kwargs); end

      # True when this handler overrides the hook for +position+
      def handles?(position)
        method_name = POSITION_TO_METHOD.fetch(position.to_s)
        self.class.instance_method(method_name).owner != CallbackHandler
      end

      class << self
        # Build one callable for +position+ from a list of handlers (and optional procs),
        # or nil when nothing is registered. First non-empty Hash wins; errors are logged.
        # @return [Proc, nil]
        def chain(position, handlers, procs = [], logger: nil)
          position = position.to_s
          method_name = POSITION_TO_METHOD.fetch(position)
          active = Array(handlers).select { |h| h.handles?(position) }
          callables = Array(procs) + active.map { |h| h.method(method_name) }
          return nil if callables.empty?

          lambda do |**kwargs|
            callables.each do |callable|
              result = callable.call(**kwargs)
              return result if result.is_a?(Hash) && !result.empty?
            rescue StandardError => e
              logger&.error("callback #{position} failed: #{e.class}: #{e.message}")
            end
            {}
          end
        end
      end
    end
  end
end
