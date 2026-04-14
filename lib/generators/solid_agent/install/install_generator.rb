# lib/generators/solid_agent/install/install_generator.rb
require 'rails/generators'
require 'rails/generators/migration'

module SolidAgent
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      desc 'Installs SolidAgent into your Rails application'

      def copy_initializer
        template 'solid_agent.rb.tt', 'config/initializers/solid_agent.rb'
      end

      def copy_migrations
        rake 'solid_agent:install:migrations'
      end

      def show_readme
        say "\nSolidAgent installed! Run `bin/rails db:migrate` to create the tables."
      end
    end
  end
end
