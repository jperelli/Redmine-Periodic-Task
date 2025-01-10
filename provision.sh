#!/bin/bash

# run copy bundle, bundle install, all with volume

docker compose run -e REDMINE_LANG=en redmine bin/rails db:migrate

# add initial data (tracker/task types, etc) to redmine database
# this script is run after redmine is up and running, so we can use the redmine container to run sql commands
docker compose run -e REDMINE_LANG=en redmine rake redmine:load_default_data

runsql() {
  echo "$1" | docker run -i --mount type=bind,source=./.volumes/sqlite/redmine.db,target=/db.db nouchka/sqlite3 /db.db
}

## set some things in database to start with plugin enabled in a project and start developing right away
### remove need to change passwd after first login
runsql "UPDATE users SET must_change_passwd=0 WHERE login='admin';"
### add a new project with periodictask module enabled
### TODO: do this only if "project1" does not exist yet in database
runsql "INSERT INTO projects (name, description, identifier, lft, rgt) VALUES ('project1', '', 'project1', 1, 2);"
runsql "INSERT INTO enabled_modules (name, project_id) VALUES ('issue_tracking', 1);"
runsql "INSERT INTO enabled_modules (name, project_id) VALUES ('periodictask', 1);"
runsql "INSERT INTO projects_trackers (project_id, tracker_id) VALUES (1, 1);"
runsql "INSERT INTO projects_trackers (project_id, tracker_id) VALUES (1, 2);"
runsql "INSERT INTO projects_trackers (project_id, tracker_id) VALUES (1, 3);"

