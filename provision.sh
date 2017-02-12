#!/bin/bash

## install rvm
RUBY_VERSION="2.1.0"
sudo apt-get -y update
sudo apt-get -y install git nodejs libmagickwand-dev
# Install ruby environment
if ! type rvm >/dev/null 2>&1; then
  curl -sSL https://rvm.io/mpapis.asc | gpg --import -
  curl -L https://get.rvm.io | bash -s stable
  source /etc/profile.d/rvm.sh
fi

if ! rvm list rubies ruby | grep ruby-${RUBY_VERSION}; then
  rvm install ${RUBY_VERSION}
fi

rvm --default use ${RUBY_VERSION}
gem install bundler

## install redmine and set the plugin
export PLUGIN=periodictask
export WORKSPACE=/app/workspace
export PATH_TO_PLUGIN=/app/repo
export PATH_TO_REDMINE=/app/redmine
export REDMINE_VERSION=3.3.2
export VERBOSE=yes
mkdir $WORKSPACE
mkdir $PATH_TO_REDMINE
bash -x /app/repo/.travis-init.sh -r || exit 1
bash -x /app/repo/.travis-init.sh -i || exit 1

## fix some permissions to start developing right away
chmod o+w -R /app/redmine/tmp
chmod og+w /app/redmine/db/redmine_development.sqlite3
chmod og+w /app/redmine/log/development.log
chmod og+w /app/redmine/db

## set some things in database to start with plugin enabled in a project and start developing right away
### remove need to change passwd after first login
echo "UPDATE users SET must_change_passwd=0 WHERE login='admin';" | /app/redmine/bin/rails db
### add a new project with periodictask module enabled
### TODO: do this only if "project1" does not exist yet in database
echo "INSERT INTO projects (name, description, identifier, lft, rgt) VALUES ('project1', '', 'project1', 1, 2);" | /app/redmine/bin/rails db
echo "INSERT INTO enabled_modules (name, project_id) VALUES ('issue_tracking', 1);" | /app/redmine/bin/rails db
echo "INSERT INTO enabled_modules (name, project_id) VALUES ('periodictask', 1);" | /app/redmine/bin/rails db
echo "INSERT INTO projects_trackers (project_id, tracker_id) VALUES (1, 1);" | /app/redmine/bin/rails db
echo "INSERT INTO projects_trackers (project_id, tracker_id) VALUES (1, 2);" | /app/redmine/bin/rails db
echo "INSERT INTO projects_trackers (project_id, tracker_id) VALUES (1, 3);" | /app/redmine/bin/rails db



## start development server
# /app/redmine/bin/rails server -b0.0.0.0 -p8080
