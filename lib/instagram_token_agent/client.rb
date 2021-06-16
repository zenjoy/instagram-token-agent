# Handles connecting to the basic display API
module InstagramTokenAgent
  class Client
    include HTTParty
    attr_accessor :config, :account

    def initialize(account, settings)
      @config = settings
      @account = account
    end

    # Fetch a fresh token from the instagram API
    #
    # @return Boolean indicating success or failure
    def refresh
      response = get(
        config.refresh_endpoint,
        query: query_params(grant_type: 'ig_refresh_token'),
        headers: { 'User-Agent' => 'Instagram Token Agent' }
      )

      if response.success?
        Store.update(account, response['access_token'], Time.now + response['expires_in'], true, nil)
      else
        Store.update(account, Store[account].value, Time.now, false, response.body)

        false
      end
    end

    def username
      get(config.user_endpoint, query: query_params(fields: 'username'))['username']
    end

    def media
      response = get(config.media_endpoint, query: query_params(fields: 'media_url'))
      # Ew. This is gross
      JSON.parse(response.body)['data'][0]['media_url'] if response.success?
    end

    private

    def get(*opts)
      self.class.get(*opts)
    end

    def query_params(extra_params = {})
      { access_token: Store[account].value }.merge(extra_params)
    end
  end
end
