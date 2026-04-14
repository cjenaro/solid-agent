module SolidAgent
  class McpController < ApplicationController
    def index
      mcp_clients = SolidAgent.configuration.mcp_clients.map do |name, config|
        {
          name: name,
          transport: config[:transport],
          command: config[:command],
          url: config[:url]
        }
      end

      render inertia: 'solid_agent/Mcp/Index', props: { mcp_clients: mcp_clients }
    end
  end
end
