require 'json'

module SolidAgent
  module HTTP
    Response = Struct.new(:status, :headers, :body, :error, keyword_init: true) do
      def success?
        status.between?(200, 299) && error.nil?
      end

      def json
        JSON.parse(body)
      end
    end
  end
end
