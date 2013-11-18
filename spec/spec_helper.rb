require 'rubygems'
require 'bundler/setup'
require 'ohm'
require 'tire'
require 'active_record'

APP_ROOT = File.expand_path(File.join(File.dirname(__FILE__) + '/..'))
Dir[File.join(APP_ROOT, "lib/*.rb")].each {|f| require f}
Dir[File.join(APP_ROOT, "lib/data_tables/*.rb")].each {|f| require f}
Dir[File.join(APP_ROOT, "spec/models/*.rb")].each {|f| require f}

DEBUG = false

Tire.configure { logger STDOUT, level: :debug } if DEBUG
Tire::Model::Search.index_prefix('test_datatable_')

RSpec.configure do |config|
  config.before(:each) do
    Tire.index("#{Tire::Model::Search.index_prefix}*"){delete}
  end
  config.after(:each) do
    #Tire.index("#{Tire::Model::Search.index_prefix}*"){delete}
  end
end
