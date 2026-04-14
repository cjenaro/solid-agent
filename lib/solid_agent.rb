require 'solid_agent/engine'
require 'solid_agent/configuration'
require 'solid_agent/model'
require 'solid_agent/models/open_ai'
require 'solid_agent/models/anthropic'
require 'solid_agent/models/google'
require 'solid_agent/models/mistral'
require 'solid_agent/models/ollama'
require 'solid_agent/http/request'
require 'solid_agent/http/response'
require 'solid_agent/http/net_http_adapter'
require 'solid_agent/http/adapters'
require 'solid_agent/types/tool_call'
require 'solid_agent/types/usage'
require 'solid_agent/types/message'
require 'solid_agent/types/response'
require 'solid_agent/types/stream_chunk'

module SolidAgent
  class Error < StandardError; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end

require 'solid_agent/tool/schema'
require 'solid_agent/tool/base'
require 'solid_agent/tool/inline_tool'
require 'solid_agent/tool/registry'
require 'solid_agent/tool/execution_engine'
require 'solid_agent/tool/mcp/transport/base'
require 'solid_agent/tool/mcp/transport/stdio'
require 'solid_agent/tool/mcp/mcp_tool'
require 'solid_agent/tool/mcp/client'

require 'solid_agent/provider/errors'
require 'solid_agent/provider/base'
require 'solid_agent/provider/registry'
require 'solid_agent/provider/openai'
require 'solid_agent/provider/anthropic'
require 'solid_agent/provider/google'
require 'solid_agent/provider/ollama'
require 'solid_agent/provider/openai_compatible'
