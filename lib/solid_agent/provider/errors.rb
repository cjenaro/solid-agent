module SolidAgent
  class ProviderError < Error
  end

  class RateLimitError < ProviderError
    attr_reader :retry_after

    def initialize(message = 'Rate limited', retry_after: nil)
      super(message)
      @retry_after = retry_after
    end
  end

  class ContextLengthError < ProviderError
    attr_reader :tokens_over

    def initialize(message = 'Context length exceeded', tokens_over: 0)
      super(message)
      @tokens_over = tokens_over
    end
  end

  class ProviderTimeoutError < ProviderError
  end
end
