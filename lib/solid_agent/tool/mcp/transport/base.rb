module SolidAgent
  module Tool
    module MCP
      module Transport
        class Base
          def send_and_receive(request)
            raise NotImplementedError
          end

          def close
            raise NotImplementedError
          end
        end
      end
    end
  end
end
