web: bundle exec puma -t 2:2 -p ${PORT:-3000} -e ${RACK_ENV:-development}
cron: bundle exec ruby worker.rb
