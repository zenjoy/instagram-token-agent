require './app'
require 'rufus/scheduler'

Sinatra::Application.environment = ENV['RACK_ENV']

def app
  App
end

$stdout.sync = true
interval = ENV['REFRESH_INTERVAL'] || '7d'

puts "Starting scheduler, will be refreshing tokens every #{interval}!"
scheduler = Rufus::Scheduler.new
scheduler.every(interval) do
  puts 'Refreshing all tokens:'
  InstagramTokenAgent::Store.accounts.each do |account|
    client = InstagramTokenAgent::Client.new(account, app.settings)
    client.refresh
    puts "- #{account}: ✅"
    sleep 1
  rescue Exception => e
    puts "- #{account}: ❌ (#{e})"
  end
end
puts 'doing my work...'
scheduler.join
