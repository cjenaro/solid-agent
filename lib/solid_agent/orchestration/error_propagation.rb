module SolidAgent
  module Orchestration
    module ErrorPropagation
      class Strategy
        attr_reader :type, :attempts

        def initialize(type, attempts: 1)
          @type = type
          @attempts = type == :retry ? attempts : 1
        end

        def execute_with_handling
          case @type
          when :retry
            execute_with_retry { yield }
          when :report_error
            execute_with_report { yield }
          when :fail_parent
            yield
          else
            yield
          end
        end

        private

        def execute_with_retry
          last_error = nil
          @attempts.times do
            begin
              return yield
            rescue => e
              last_error = e
            end
          end
          "Error after #{@attempts} attempts: #{last_error.message}"
        end

        def execute_with_report
          yield
        rescue => e
          "Error: #{e.message}"
        end
      end

      DEFAULT = Strategy.new(:report_error)
    end
  end
end
