require 'json'
require 'net/http'
require 'uri'
require 'solid_agent/tool/mcp/transport/base'

module SolidAgent
  module Tool
    module MCP
      module Transport
        class SSE < Base
          attr_reader :url

          def initialize(url:, headers: {})
            @url = url
            @headers = headers
            @connection = nil
          end

          def connect
            return if @connection
            @uri = URI.parse(@url)
            @connection = true
          end

          def send_and_receive(request)
            connect
            json_str = JSON.generate(request)
            uri = @uri || URI.parse(@url)

            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = uri.scheme == 'https'
            http.read_timeout = 60

            # Send JSON-RPC request via POST to the MCP endpoint
            post_req = Net::HTTP::Post.new(uri.request_uri)
            post_req['Content-Type'] = 'application/json'
            post_req['Accept'] = 'application/json, text/event-stream'
            @headers.each { |k, v| post_req[k] = v }
            post_req.body = json_str

            response = http.request(post_req)

            unless response.is_a?(Net::HTTPSuccess)
              raise Error, "MCP SSE request failed: HTTP #{response.code} - #{response.body&.truncate(200)}"
            end

            # Parse the response - could be direct JSON or SSE stream
            body = response.body.to_s.strip

            if body.start_with?('data:')
              # SSE format - extract the data
              lines = body.split("\n")
              data_lines = lines.select { |l| l.start_with?('data:') }
              data_lines.map { |l| l.sub('data:', '').strip }.first || '{}'
            else
              body
            end
          rescue Errno::ECONNREFUSED => e
            raise Error, "MCP SSE connection refused: #{e.message}"
          rescue Errno::ENOENT, Errno::EACCES => e
            raise Error, e.message
          end

          def close
            @connection = nil
          end
        end
      end
    end
  end
end
