#   Copyright (c) 2010-2011, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

set :config_yaml, YAML.load_file(File.dirname(__FILE__) + '/deploy_config.yml')

$:.unshift(File.expand_path('./lib', ENV['rvm_path'])) # Для работы rvm
require 'rvm/capistrano' # Для работы rvm

require 'bundler/capistrano'
set :bundle_dir, ''

set :stages, ['production', 'staging']
set :default_stage, 'staging'
require 'capistrano/ext/multistage'

set :unicorn_conf, "#{deploy_to}/current/config/unicorn.rb"
set :unicorn_pid, "#{deploy_to}/shared/pids/unicorn.pid"

set :application, 'diaspora'
set :scm, :git
set :use_sudo, false
set :scm_verbose, true
set :repository_cache, "remote_cache"
set :deploy_via, :checkout
#set :deploy_to, "/srv/#{application}"

set :domain, "git@git.ndc-kvazar.com.ua" # Это необходимо для деплоя через ssh. Именно ради этого я настоятельно советовал сразу же залить на сервер свой ключ, чтобы не вводить паролей.
#set :rails_env, "production"
set :rvm_ruby_string, '1.9.2' # Это указание на то, какой Ruby интерпретатор мы будем использовать.
set :rvm_type, :user # Указывает на то, что мы будем использовать rvm, установленный у пользователя, от которого происходит деплой, а не системный rvm.

# Bonus! Colors are pretty!
def red(str)
  "\e[31m#{str}\e[0m"
end

before_exec do |server|
  ENV["BUNDLE_GEMFILE"] = "#{rails_root}/Gemfile"
end

# Figure out the name of the current local branch
def current_git_branch
  branch = `git symbolic-ref HEAD 2> /dev/null`.strip.gsub(/^refs\/heads\//, '')
  puts "Deploying branch #{red branch}"
  branch
end

# Set the deploy branch to the current branch
set :branch, current_git_branch

# Далее идут правила для перезапуска unicorn. Их стоит просто принять на веру - они работают.
# В случае с Rails 3 приложениями стоит заменять bundle exec unicorn_rails на bundle exec unicorn
namespace :deploy do
  task :symlink_config_files do
    run "ln -s -f #{shared_path}/config/database.yml #{current_path}/config/database.yml"
    run "ln -s -f #{shared_path}/config/application.yml #{current_path}/config/application.yml"
    run "ln -s -f #{shared_path}/config/oauth_keys.yml #{current_path}/config/oauth_keys.yml"
  end

  task :symlink_cookie_secret do
    run "ln -s -f #{shared_path}/config/initializers/secret_token.rb #{current_path}/config/initializers/secret_token.rb"
  end

  task :bundle_static_assets do
    run "cd #{current_path} && sass --update public/stylesheets/sass:public/stylesheets"
    run "cd #{current_path} && bundle exec jammit"
  end

  task :restart do
    run "if [ -f #{unicorn_pid} ] && [ -e /proc/$(cat #{unicorn_pid}) ]; then kill -USR2 `cat #{unicorn_pid}`; else cd #{deploy_to}/current && bundle exec unicorn -c #{unicorn_conf} -E #{rails_env} -D; fi"

    #thins = capture "svstat /service/thin*"
    #matches = thins.match(/(thin_\d+):/).captures

    #matches.each_with_index do |thin, index|
    #  unless index == 0
    #    puts "sleeping for 20 seconds"
    #    sleep(20)
    #  end
    #  run "svc -t /service/#{thin}"
    #end

    run "svc -t /service/resque_worker*"
  end

  task :kill do
    run "if [ -f #{unicorn_pid} ] && [ -e /proc/$(cat #{unicorn_pid}) ]; then kill -QUIT `cat #{unicorn_pid}`; fi"
    #run "svc -k /service/thin*"
    run "svc -k /service/resque_worker*"
  end

  task :start do
    run "bundle exec unicorn_rails -c #{unicorn_conf} -E #{rails_env} -D"
    #run "svc -u /service/thin*"
    run "svc -u /service/resque_worker*"
  end

  task :stop do
    run "if [ -f #{unicorn_pid} ] && [ -e /proc/$(cat #{unicorn_pid}) ]; then kill -QUIT `cat #{unicorn_pid}`; fi"
    #run "svc -d /service/thin*"
    run "svc -d /service/resque_worker*"
  end

  desc 'Copy resque-web assets to public folder'
  task :copy_resque_assets do
    target = "#{release_path}/public/resque-jobs"
    run "cp -r `cd #{release_path} && bundle show resque`/lib/resque/server/public #{target}"
  end
end

after "deploy:symlink", "deploy:symlink_config_files", "deploy:symlink_cookie_secret", "deploy:bundle_static_assets", 'deploy:copy_resque_assets'

        require './config/boot'
        require 'hoptoad_notifier/capistrano'
