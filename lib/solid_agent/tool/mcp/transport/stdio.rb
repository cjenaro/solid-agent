require 'json'
require 'open3'
require 'solid_agent/tool/mcp/transport/base'

module SolidAgent
  module Tool
    module MCP
      module Transport
        class Stdio < Base
          attr_reader :command, :args, :env

          def initialize(command:, args: [], env: {})
            @command = command
            @args = args
            @env = env
            @stdin = nil
            @stdout = nil
            @stderr = nil
            @wait_thr = nil
          end

          def connect
            return if @stdin

            @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(@env, @command, *@args)
          end

          def send_and_receive(request)
            connect
            json_str = JSON.generate(request)
            @stdin.puts(json_str)
            @stdin.flush

            response_line = @stdout.gets
            raise Error, 'MCP server closed connection' unless response_line

            response_line.strip
          rescue Errno::ENOENT, Errno::EACCES => e
            raise Error, e.message
          end

          def close
            @stdin&.close
            @stdout&.close
            @stderr&.close
            @wait_thr&.kill
            @stdin = @stdout = @stderr = @wait_thr = nil
          end
        end
      end
    end
  end
end
