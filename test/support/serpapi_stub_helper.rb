# Shared helpers for stubbing SerpApi HTTP calls in tool tests.
module SerpApiStubHelper
  # Stub SerpApi::Client.new so that every call to `client.search(...)` inside
  # the block returns +response_data+ (a Hash with symbolized keys, as SerpAPI
  # returns in production).
  def stub_serpapi(response_data)
    fake_client = Object.new
    fake_client.define_singleton_method(:search) { |**_kwargs| response_data }
    SerpApi::Client.stub(:new, fake_client) { yield }
  end
end
