require 'solid_agent/engine'
require 'solid_agent/configuration'
require 'solid_agent/model'
require 'solid_agent/models/open_ai'
require 'solid_agent/models/anthropic'
require 'solid_agent/models/google'
require 'solid_agent/models/mistral'
require 'solid_agent/models/ollama'

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
