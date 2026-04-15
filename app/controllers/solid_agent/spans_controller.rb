module SolidAgent
  class SpansController < ApplicationController
    def show
      @span = Span.find(params[:id])
    end
  end
end
