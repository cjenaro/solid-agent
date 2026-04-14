module SolidAgent
  module HTTP
    module Adapters
      BUILT_IN = {
        net_http: 'SolidAgent::HTTP::NetHttpAdapter'
      }.freeze

      def self.resolve(adapter)
        case adapter
        when Symbol
          klass_name = BUILT_IN[adapter]
          raise SolidAgent::Error, "Unknown HTTP adapter: #{adapter}" unless klass_name

          klass_name.constantize.new
        when Class
          adapter.new
        when nil
          NetHttpAdapter.new
        else
          adapter
        end
      end
    end
  end
end
