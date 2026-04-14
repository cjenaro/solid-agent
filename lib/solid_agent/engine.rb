module SolidAgent
  class Engine < ::Rails::Engine
    isolate_namespace SolidAgent

    config.generators do |g|
      g.test_framework :minitest
    end
  end
end
