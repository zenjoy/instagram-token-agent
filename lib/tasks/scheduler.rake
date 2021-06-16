desc 'Refresh the token value with the Instagram API'
task refresh: :environment do
  InstagramTokenAgent::Store.accounts.each do |account|
    client = InstagramTokenAgent::Client.new(account, app.settings)
    client.refresh
    sleep 1
  end
end
