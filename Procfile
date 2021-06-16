web: bundle exec puma -t 2:2 -p ${PORT:-3000} -e ${RACK_ENV:-development}
worker: bundle exec ruby worker.rb
foreman: bundle exec foreman
