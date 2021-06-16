desc 'Perform initial setup of the database'
task setup: :environment do
  Rake::Task['migrate'].invoke

  # Seed the initial row in the table with the token from the environment.
  starting_tokens = ENV.keys.select { |t| t =~ /^STARTING_TOKEN_/ }

  if starting_tokens && starting_tokens.length > 0
    starting_tokens.each do |value|
      account_name = value.gsub(/^STARTING_TOKEN_/, '').downcase

      InstagramTokenAgent::Store.execute(
        'INSERT INTO tokens (account, value, expires_at, success) VALUES ($1, $2, $3, $4)', [account_name, ENV[value], Time.now - 1,
                                                                                             true]
      )
    end

    # Run an initial refresh to populate expiries etc.
    InstagramTokenAgent::Store.accounts.each do |account|
      client = InstagramTokenAgent::Client.new(account, app)
      client.refresh
    end
  end

  puts 'Setup done!'
end

desc 'Create the DB tables'
task migrate: :environment do
  # Create the table in the DB. This is assumed to be Postgres.
  InstagramTokenAgent::Store.execute <<-SQL
    CREATE TABLE IF NOT EXISTS tokens (
      account         varchar(256),
      value           varchar(256),
      created_at      timestamp DEFAULT current_timestamp,
      updated_at      timestamp DEFAULT current_timestamp,
      expires_at      timestamp,
      success         boolean,
      response_body   text
    )
  SQL
end

desc 'Reset the database'
task reset: :environment do
  InstagramTokenAgent::Store.execute <<-SQL
    DROP TABLE IF EXISTS tokens
  SQL

  Rake::Task['migrate'].invoke
end
