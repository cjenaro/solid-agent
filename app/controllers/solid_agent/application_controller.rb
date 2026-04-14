module SolidAgent
  class ApplicationController < ActionController::Base
    layout 'solid_agent'

    before_action :check_dashboard_enabled

    private

    def check_dashboard_enabled
      return if SolidAgent.configuration.dashboard_enabled

      render plain: 'SolidAgent dashboard is disabled.', status: :not_found
    end
  end
end
