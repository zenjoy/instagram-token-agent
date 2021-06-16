web: bundle exec puma -t 2:2 -p ${PORT:-3000} -e ${RACK_ENV:-development}
worker: bundle exec ruby worker.rb
all: bundle exec foreman start -m "web=1,worker=1"
refresh: bundle exec rake refresh
