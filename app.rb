require 'dotenv'
require 'bundler'

Dotenv.load
Bundler.require

require_relative 'lib/instagram_token_agent'

class App < Sinatra::Base
  register Sinatra::ActiveRecordExtension
  register Sinatra::CrossOrigin

  # Nicer debugging in dev mode
  configure :development do
    require 'pry'
    require 'better_errors'
    use BetterErrors::Middleware
    BetterErrors.application_root = __dir__
  end

  # -------------------------------------------------
  # Overall configuration - done here rather than yml files to reduce dependencies
  # -------------------------------------------------
  configure do
    set :app_name, ENV['APP_NAME'] # The app needs to know its own name/url.
    set :app_url, ENV['APP_URL'] || "https://#{settings.app_name}.herokuapp.com"

    enable :cross_origin
    disable :show_exceptions
    enable :raise_errors

    set :help_pages,        !(ENV['HIDE_HELP_PAGES']) || false # Whether to display the welcome pages or not
    set :allow_origin,      if ENV['ALLOWED_DOMAINS']
                              (ENV['ALLOWED_DOMAINS'].split(' ').map do |d|
                                 "https://#{d}"
                               end)
                            else
                              settings.app_url
                            end
    set :allow_methods,     %i[get options] # Only allow GETs and OPTION requests
    set :allow_credentials, false                                                 # We have no need of credentials!

    set :default_starting_token, 'copy_token_here'                                # The 'Deploy to Heroku' button sets this environment value
    set :js_constant_name, ENV['JS_CONSTANT_NAME'] || 'InstagramToken' # The name of the constant used in the JS snippet

    # scheduled mode would be more efficient, but currently doesn't work
    # because Temporize free accounts don't support dates more than 7 days in the future
    set :token_refresh_mode, ENV['REFRESH_MODE'] || :cron                         # cron | scheduled
    set :token_expiry_buffer, 2 * 24 * 60 * 60                                    # 2 days before expiry
    set :token_refresh_frequency, ENV['REFRESH_FREQUENCY'].to_s || :weekly        # daily, weekly, monthly

    set :refresh_endpoint,  'https://graph.instagram.com/refresh_access_token'    # The endpoint to hit to extend the token
    set :user_endpoint,     'https://graph.instagram.com/me'                      # The endpoint to hit to fetch user profile
    set :media_endpoint,    'https://graph.instagram.com/me/media'                # The endpoint to hit to fetch the user's media

    set :refresh_webhook, (ENV['WEBHOOK_SECRET'] ? true : false) # Check if Temporize is configured
    set :webhook_secret, ENV['WEBHOOK_SECRET'] # The secret value used to sign external, incoming requests

    set :logger, Logger.new(STDOUT)
  end

  # Make sure everything is set up before we try to do anything else
  before do
    ensure_configuration!
  end

  # Switch for the help pages
  unless settings.help_pages?
    ['/', '/status', '/setup'].each do |help_page|
      before help_page do
        halt 204
      end
    end
  end

  # The home page
  get '/' do
    haml(:index, layout: :'layouts/default')
  end

  # Requested by the index page, this checks the status of the
  # refresh task and talks to Instagram to ensure everything's set up.
  get '/status' do
    account_with_issue = ''
    ok = InstagramTokenAgent::Store.accounts.all? do |account|
      account_with_issue = account
      client ||= InstagramTokenAgent::Client.new(account, settings)
      client.username.present?
    rescue StandardError
      false
    end

    if ok
      halt 201
    else
      logger.info("There is a problem with the token for account #{account_with_issue}")
      halt 401
    end
  end

  get '/:account/status' do
    @client ||= InstagramTokenAgent::Client.new(account, settings) if InstagramTokenAgent::Store.configured?(account)

    haml(:status, layout: :'layouts/default')
  end

  # Show the setup page - mostly for dev, this is shown automatically in production
  get '/setup' do
    app_info
    haml(:setup, layout: :'layouts/default')
  end

  # Allow a manual refresh, but only if the previous attempt failed
  post '/:account/refresh' do
    if InstagramTokenAgent::Store[account].success?
      halt 204
    else
      client = InstagramTokenAgent::Client.new(account, settings)
      client.refresh
      redirect '/setup'
    end
  end

  # -------------------------------------------------
  # The Token API
  # This is a good candidate for a Sinatra namespace, but sinatra-contrib needs updating
  # -------------------------------------------------

  # Some clients will make an OPTIONS pre-flight request before doing CORS requests
  options '/:account/token' do
    cross_origin

    response.headers['Allow'] = settings.allow_methods
    response.headers['Access-Control-Allow-Headers'] =
      'X-Requested-With, X-HTTP-Method-Override, Content-Type, Cache-Control, Accept'

    204 # 'No Content'
  end

  # Return the token itself
  # Formats:
  #  - .js
  #  - .json
  #  - plain text (default)
  #
  get '/:account/token:format?' do
    account_store = InstagramTokenAgent::Store[account]

    # Tokens remain active even after refresh, so we can set the cache up close to FB's expiry
    cache_control :public, max_age: account_store.expires - Time.now - settings.token_expiry_buffer

    cross_origin

    response_body = case params['format']
                    when '.js'
                      content_type 'application/javascript'

                      @js_constant_name = params[:const] || settings.js_constant_name

                      erb(:'javascript/snippet.js')

                    when '.json'
                      content_type 'application/json'
                      json(token: account_store.value)
                    else
                      account_store.value
                    end

    etag Digest::SHA1.hexdigest(response_body + (response.headers['Access-Control-Allow-Origin'] || '*'))

    response_body
  end

  # -------------------------------------------------
  # Webhook endpoints
  #
  # Used by the Temporize scheduling service to trigger a refresh externally
  # -------------------------------------------------

  if settings.refresh_webhook?
    post '/hooks/refresh/:signature' do
      if params[:signature] == settings.webhook_secret
        InstagramTokenAgent::Store.accounts.each do |account|
          client = InstagramTokenAgent::Client.new(account, settings)
          client.refresh
        end
        halt 201
      else
        halt 403
      end
    end
  end

  # -------------------------------------------------
  # Error pages
  # -------------------------------------------------

  not_found do
    haml(:not_found, layout: :'layouts/default')
  end

  error do
    haml(:error, layout: :'layouts/default')
  end

  helpers do
    def account
      params['account']
    end

    def available_accounts
      InstagramTokenAgent::Store.accounts
    end

    # Provide some info sourced from the app.json file
    def app_info
      @app_info ||= InstagramTokenAgent::AppInfo.info
    end

    # Check that the configuration looks right to continue
    def configured?
      return false unless check_allowed_domains
      return false unless check_starting_token

      true
    end

    # Show the setup screen if we're not yet ready to go.
    def ensure_configuration!
      halt haml(:setup, layout: :'layouts/default') unless configured?
    end

    def check_allowed_domains
      ENV['ALLOWED_DOMAINS'].present? and !ENV['ALLOWED_DOMAINS'].match(/\*([^.]|$)/) # Disallow including * in the allow list
    end

    def check_starting_token
      InstagramTokenAgent::Store.initialized? || ENV.keys.any? { |t| t =~ /^STARTING_TOKEN_/ }
    end

    def check_token_status
      InstagramTokenAgent::Store.success?
    end

    def latest_instagram_response
      account_with_errors = {}
      InstagramTokenAgent::Store.accounts.each do |a|
        unless InstagramTokenAgent::Store[a].response_body.nil?
          account_with_errors[a] = JSON.parse(InstagramTokenAgent::Store[a].response_body)
        end
      end

      JSON.pretty_generate(account_with_errors)
    end
  end
end
