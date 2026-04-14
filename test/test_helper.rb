require 'bundler/setup'

ENV['RAILS_ENV'] = 'test'

require 'active_record'
require 'active_support'
require 'active_support/test_case'
require 'rails'

ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: ':memory:'
)

ActiveSupport::TestCase.test_order = :random
