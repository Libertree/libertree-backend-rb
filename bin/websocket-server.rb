require 'libertree/db'

# Sequel wants us to connect to the db before defining models.  As model
# definitions are loaded when 'libertree/server' is required, we have to do
# this first.
if ENV['DATABASE_URL']
  # Heroku
  ENV['DATABASE_URL'] =~ %r{postgres://(.+?):(.+?)@(.+?):(\d+)/(.+?)$}
  Libertree::DB.config = {
    'username' => $1,
    'password' => $2,
    'host' => $3,
    'port' => $4,
    'database' => $5,
  }
else
  if ARGV[1].nil?
    $stderr.puts "no database configuration file given; assuming #{File.dirname( __FILE__ ) }/../database.yaml"
    db_config = "#{File.dirname( __FILE__ ) }/../database.yaml"
  else
    db_config = ARGV[1]
  end

  Libertree::DB.load_config db_config
end
Libertree::DB.dbh

require 'libertree/model'
require 'libertree/server/websocket'

Thread.abort_on_exception = true

conf = YAML.load(File.read("#{File.dirname( __FILE__ ) }/../defaults.yaml"))
if ARGV[0]
  conf = conf.merge(YAML.load(File.read(ARGV[0])))
else
  {
    'LIBERTREE_WEBSOCKET_LISTEN_HOST' => 'websocket_listen_host',
    # This port is initialized/provided by Heroku
    'PORT' => 'websocket_port',
  }.each do |env_key, conf_key|
    conf[conf_key] = ENV.fetch(env_key, conf[conf_key])
  end
end

if conf['pid_dir']
  if ! Dir.exists?(conf['pid_dir'])
    FileUtils.mkdir_p conf['pid_dir']
  end
  pid_file = File.join(conf['pid_dir'], 'websocket-server.pid')
  File.open(pid_file, 'w') do |f|
    f.print Process.pid
  end
end

EventMachine.run do
  Libertree::Server::Websocket.run(conf)
end
