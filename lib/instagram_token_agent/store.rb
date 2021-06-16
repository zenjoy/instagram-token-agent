module InstagramTokenAgent
  # Handle interfacing with the database, updating and retrieving values
  class Store
    class Token
      attr_accessor :data

      def initialize(row)
        @data = OpenStruct.new({
                                 value: row['value'],
                                 success: row['success'],
                                 response_body: row['response_body'],
                                 expires: row['expires_at'],
                                 created: row['created_at']
                               })
      end

      # Accessors for the token data
      def value
        data.value
      end

      def expires
        data.expires
      end

      def success?
        data.success == true
      end

      def response_body
        data.response_body
      end

      def created
        data.created
      end
    end

    # Execute the given SQL and params
    def self.execute(sql, params = [])
      binds = params.map { |p| [nil, p] }
      ActiveRecord::Base.connection_pool.with_connection { |con| con.exec_query(sql, 'sql', binds) }
    end

    # Fetch the value row data and memoize
    # This doesn't check if the token has expired - we'll let the client sort
    # that out with Instagram.
    #
    # @return Proc
    def self.data
      return @data if @data.present?

      rows = execute('SELECT account, value, expires_at, created_at, success, response_body FROM tokens').to_a
      @data = {}
      rows.each do |row|
        @data[row['account']] = Token.new(row)
      end
      @data
    end

    # Update the token value in the store
    # This assumes there's only ever a single row in the table
    # The initial insert is done via the setup task.
    def self.update(account, value, expires, success = true, response_body = nil)
      execute('UPDATE tokens SET updated_at = $1, value = $2, expires_at = $3, success = $4, response_body = $5 WHERE account = $6',
              [Time.now, value, expires, success, response_body, account])
    end

    def self.[](account)
      data[account]
    end

    def self.accounts
      @accounts ||= data.keys
    end

    def self.success?
      data.values.all? { |token| token.success? && token.value.present? }
    end

    def self.configured?(account)
      Array(accounts).include?(account)
    end
  end
end
