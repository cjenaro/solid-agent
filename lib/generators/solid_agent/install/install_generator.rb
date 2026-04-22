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

      def mount_engine
        mount_statement = "  mount SolidAgent::Engine, at: '/solid_agent'"
        routes_file = 'config/routes.rb'

        if File.exist?(routes_file)
          routes_content = File.read(routes_file)

          # Check if mount already exists (case-insensitive, allows whitespace variations)
          unless routes_content.match?(/mount\s+SolidAgent::Engine/i)
            # Insert at the end, before the final 'end' if present
            if routes_content.strip.end_with?('end')
              # Insert before the last 'end'
              last_end_index = routes_content.rindex(/\n\s*end\s*\z/)
              if last_end_index
                routes_content.insert(last_end_index + 1, "#{mount_statement}\n")
              else
                routes_content << "\n#{mount_statement}\n"
              end
            else
              routes_content << "\n#{mount_statement}\n"
            end

            File.write(routes_file, routes_content)
            say "Added mount statement to #{routes_file}"
          else
            say "Mount statement already exists in #{routes_file}", :green
          end
        else
          say "Warning: #{routes_file} not found - please manually add: #{mount_statement}", :yellow
        end
      end

      def show_readme
        say "\nSolidAgent installed! Run `bin/rails db:migrate` to create the tables."
      end
    end
  end
end
