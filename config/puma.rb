root = "#{Dir.getwd}"

environment 'development'

activate_control_app "tcp://127.0.0.1:9293"
bind "unix://#{root}/tmp/puma.sock"
bind "tcp://0.0.0.0:9292"
pidfile "#{root}/tmp/pids/puma.pid"
rackup "#{root}/config.ru"
state_path "#{root}/tmp/pids/puma.state"
daemonize false
