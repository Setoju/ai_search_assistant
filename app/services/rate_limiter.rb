class RateLimiter
  WINDOW_SECONDS = 60
  MAX_REQUESTS_PER_WINDOW = 10 # 10 requests per minute per IP

  class RateLimitExceeded < StandardError
    attr_reader :retry_after

    def initialize(retry_after)
      @retry_after = retry_after
      super("Rate limit exceeded. Please try again in #{retry_after} seconds.")
    end
  end

  def initialize
    @store = {}
    @mutex = Mutex.new # Ensure thread safety, so there's no race condition
  end

  def check!(identifier)
    @mutex.synchronize do
      cleanup_expired!

      key = identifier.to_s
      now = Time.now.to_i
      window_start = now - WINDOW_SECONDS

      @store[key] ||= []
      @store[key].reject! { |timestamp| timestamp < window_start } # Remove timestamps outside the current window

      if @store[key].length >= MAX_REQUESTS_PER_WINDOW
        oldest = @store[key].first
        retry_after = WINDOW_SECONDS - (now - oldest)
        raise RateLimitExceeded.new([ retry_after, 1 ].max)
      end

      @store[key] << now
      true
    end
  end

  def remaining(identifier)
    @mutex.synchronize do
      key = identifier.to_s
      now = Time.now.to_i
      window_start = now - WINDOW_SECONDS

      @store[key] ||= []
      @store[key].reject! { |timestamp| timestamp < window_start }

      MAX_REQUESTS_PER_WINDOW - @store[key].length
    end
  end

  private

  def cleanup_expired!
    now = Time.now.to_i
    cutoff = now - WINDOW_SECONDS * 2
    @store.delete_if { |_, timestamps| timestamps.all? { |t| t < cutoff } }
  end
end
