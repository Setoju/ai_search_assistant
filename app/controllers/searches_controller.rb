class SearchesController < ApplicationController
  RATE_LIMITER = RateLimiter.new

  def index
  end

  def create
    begin
      RATE_LIMITER.check!(request.remote_ip)
    rescue RateLimiter::RateLimitExceeded => e
      @error = e.message
      @remaining = 0
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("search-results", partial: "searches/error", locals: { error: @error }) }
        format.html { render :index, status: :too_many_requests }
      end
      return
    end

    query = params[:query]

    orchestrator = Orchestrator.new
    result = orchestrator.process(query)

    @remaining = RATE_LIMITER.remaining(request.remote_ip)

    if result[:success]
      @response = result[:response]
      @metadata = result[:metadata]
    else
      @error = result[:error]
    end

    respond_to do |format|
      format.turbo_stream do
        if @error
          render turbo_stream: turbo_stream.replace("search-results", partial: "searches/error", locals: { error: @error })
        else
          render turbo_stream: turbo_stream.replace("search-results", partial: "searches/results", locals: { response: @response, metadata: @metadata, remaining: @remaining })
        end
      end
      format.html { render :index }
    end
  rescue => e
    Rails.logger.error("[SearchesController] Unhandled error: #{e.class} - #{e.message}")
    @error = "Something went wrong. Please try again."
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("search-results", partial: "searches/error", locals: { error: @error }) }
      format.html { render :index, status: :internal_server_error }
    end
  end
end
