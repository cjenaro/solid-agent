module SolidAgent
  class SpansController < ApplicationController
    def show
      span = Span.find(params[:id])
      render inertia: 'solid_agent/Spans/Show', props: {
        span: span.as_json(only: %i[id span_type name status tokens_in tokens_out started_at completed_at input output metadata])
      }
    end
  end
end
