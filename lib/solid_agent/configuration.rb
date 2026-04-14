module SolidAgent
  class Configuration
    attr_accessor :default_provider, :default_model, :dashboard_enabled,
                  :dashboard_route_prefix, :vector_store, :embedding_provider,
                  :embedding_model, :http_adapter, :trace_retention,
                  :providers, :mcp_clients

    def initialize
      @default_provider = :openai
      @default_model = nil
      @dashboard_enabled = true
      @dashboard_route_prefix = 'solid_agent'
      @vector_store = :sqlite_vec
      @embedding_provider = :openai
      @embedding_model = 'text-embedding-3-small'
      @http_adapter = :net_http
      @trace_retention = 30.days
      @providers = {}
      @mcp_clients = {}
    end

    def validate!
      return if @default_provider.is_a?(Symbol) || @default_provider.nil?

      raise Error, 'default_provider must be a symbol'
    end
  end
end
