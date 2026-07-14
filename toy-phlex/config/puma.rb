threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

port ENV.fetch("PORT", 3001)

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
