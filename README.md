periodictask
============

In some projects there are tasks that need to be assigned on a schedule.
Such as check the ssl registration once per year or run security checks every 3 months

On each project it will add a new tab named Scheduled Tasks just go there to add your task

Installation
------------

    cd /usr/local/share/redmine
    git clone -b redmine2 http://github.com:/perelli/Redmine-Periodic-Task.git plugins/periodictask
    rake redmine:plugins:migrate NAME=periodictask RAILS_ENV=production
    apache2ctl graceful

Note: Copy the files into {redmine-base-dir}/plugins/periodictask. Do not use the directory name of the repository.

Uninstallation
--------------

    cd /usr/local/share/redmine
    rake redmine:plugins:migrate NAME=periodictask VERSION=0 RAILS_ENV=production
    rm -rf plugins/periodictask
    apache2ctl graceful

Configuration
-------------

As root do `crontab -e` and add this to the last line

    0 1 * * * cd /var/www/<redminedir>; rake redmine:check_periodictasks RAILS_ENV="production"

You can also make it run once per hour

    0 * * * * cd /var/www/<redminedir>; rake redmine:check_periodictasks RAILS_ENV="production"

Or even every 10 minutes

    0/10 * * * * cd /var/www/<redminedir>; rake redmine:check_periodictasks RAILS_ENV="production"
