require 'libertree/db'

if ARGV[0].nil?
  $stderr.puts "#{$0} <config.yaml> <database.yaml>"
  exit 1
end

if ARGV[1].nil?
  $stderr.puts "no database configuration file given; assuming #{File.dirname( __FILE__ ) }/../database.yaml"
  db_config = "#{File.dirname( __FILE__ ) }/../database.yaml"
else
  db_config = ARGV[1]
end

########################
# Sequel wants us to connect to the db before defining models.  As model
# definitions are loaded when 'libertree/server' is required, we have to do
# this first.
Libertree::DB.load_config db_config
Libertree::DB.dbh
########################

require 'libertree/model'
require 'libertree/server/websocket'

Thread.abort_on_exception = true

conf = YAML.load(
  File.read("#{File.dirname( __FILE__ ) }/../defaults.yaml")
).merge YAML.load(File.read(ARGV[0]))

EventMachine.run do
  Libertree::Server::Websocket.run(conf)
end
