require 'net/http'
require 'uri'

module SolidAgent
  module HTTP
    class NetHttpAdapter
      def call(request)
        uri = URI.parse(request.url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = 120
        http.open_timeout = 30

        net_request = build_request(uri, request)
        apply_headers(net_request, request)

        net_request['X-Stream'] = 'true' if request.stream

        response = http.request(net_request)

        if response.is_a?(Net::HTTPSuccess)
          Response.new(status: response.code.to_i, headers: response.each_header.to_h, body: response.body, error: nil)
        else
          Response.new(status: response.code.to_i, headers: {}, body: response.body,
                       error: "HTTP #{response.code}: #{response.message}")
        end
      rescue StandardError => e
        Response.new(status: 0, headers: {}, body: nil, error: e.message)
      end

      private

      def build_request(uri, request)
        case request.method
        when :get
          Net::HTTP::Get.new(uri.request_uri)
        when :post
          Net::HTTP::Post.new(uri.request_uri).tap { |req| req.body = request.body }
        when :put
          Net::HTTP::Put.new(uri.request_uri).tap { |req| req.body = request.body }
        when :delete
          Net::HTTP::Delete.new(uri.request_uri)
        else
          raise ArgumentError, "Unsupported HTTP method: #{request.method}"
        end
      end

      def apply_headers(net_request, request)
        request.headers.each do |key, value|
          net_request[key] = value
        end
      end
    end
  end
end
