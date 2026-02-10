# frozen_string_literal: true

module Conductor
  module Workflow
    module Llm
      # ListMcpToolsTask - List available tools from an MCP server
      class ListMcpToolsTask < TaskInterface
        # @param task_ref_name [String] Unique reference name
        # @param mcp_server [String] MCP server integration name
        # @param headers [Hash<String,String>, nil] Optional HTTP headers
        # @param task_name [String, nil] Task definition name
        def initialize(task_ref_name, mcp_server, headers: nil, task_name: nil)
          input_params = {
            'mcpServer' => mcp_server
          }
          input_params['headers'] = headers if headers

          super(
            task_reference_name: task_ref_name,
            task_type: TaskType::LIST_MCP_TOOLS,
            task_name: task_name || 'list_mcp_tools',
            input_parameters: input_params
          )
        end
      end
    end
  end
end
