# frozen_string_literal: true

module Conductor
  module Workflow
    module Llm
      # CallMcpToolTask - Invoke a tool on an MCP server
      class CallMcpToolTask < TaskInterface
        # @param task_ref_name [String] Unique reference name
        # @param mcp_server [String] MCP server integration name
        # @param method [String] Tool method name
        # @param arguments [Hash, nil] Arguments to pass to the tool
        # @param headers [Hash<String,String>, nil] Optional HTTP headers
        # @param task_name [String, nil] Task definition name
        def initialize(task_ref_name, mcp_server, method,
                       arguments: nil, headers: nil, task_name: nil)
          input_params = {
            'mcpServer' => mcp_server,
            'method' => method,
            'arguments' => arguments || {}
          }
          input_params['headers'] = headers if headers

          super(
            task_reference_name: task_ref_name,
            task_type: TaskType::CALL_MCP_TOOL,
            task_name: task_name || 'call_mcp_tool',
            input_parameters: input_params
          )
        end
      end
    end
  end
end
