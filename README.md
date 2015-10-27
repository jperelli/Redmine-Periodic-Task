[![Build Status](https://travis-ci.org/jperelli/Redmine-Periodic-Task.svg)](https://travis-ci.org/jperelli/Redmine-Periodic-Task)

periodictask
============

In some projects there are tasks that need to be assigned on a schedule.
Such as check the ssl registration once per year or run security checks every 3 months

After you installed the plugin you can add it as a module to a project that already exists
or activate it as default module for new projects. On each project it will add a new tab 
named "Periodic Task" - just go there to add your tasks.

Note about redmine version support
----------------------------------

This fork (jperelli) supports now redmine v2 and v3.

Redmine v1 support has been dropped in favor of newer v3. If you still need redmine v1 support, please use redmine2 branch, that supports v1 and v2.

Support table :

<table>
  <tr>
    <td rowspan="2">git branch</td>
    <td colspan="3">redmine version support</td>
  </tr>
  <tr>
    <td>1.x</td>
    <td>2.x</td>
    <td>3.x</td>
  </tr>
  <tr>
    <td>master</td>
    <td>Unknown</td>
    <td>Yes</td>
    <td>Yes</td>
  </tr>
  <tr>
    <td>redmine2</td>
    <td>Yes</td>
    <td>Yes</td>
    <td>No</td>
  </tr>
</table>

To use redmine2 branch, when cloning use `-b redmine2` like this `git clone -b redmine2 http://github.com:/jperelli/Redmine-Periodic-Task.git plugins/periodictask`

Installation
------------

    cd /usr/local/share/redmine
    git clone http://github.com:/jperelli/Redmine-Periodic-Task.git plugins/periodictask
    rake redmine:plugins:migrate NAME=periodictask RAILS_ENV=production
    apache2ctl graceful

Note: Copy the files into {redmine-base-dir}/plugins/periodictask. Do not use the directory name of the repository.

Upgrade
-------

    cd /usr/local/share/redmine/plugins/periodictask
    git pull
    rake redmine:plugins:migrate NAME=periodictask RAILS_ENV=production
    apache2ctl graceful

Note: If you copy the files into {redmine-base-dir}/plugins/periodictask please update them instead of using git pull.

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

    */10 * * * * cd /var/www/<redminedir>; rake redmine:check_periodictasks RAILS_ENV="production"

If you want to substitute variable `MONTHNAME` with localized version (`de`, `tr`, `en` or `ru`) please add `LOCALE="de"` to cronjob like this

    0 * * * * cd /var/www/<redminedir>; rake redmine:check_periodictasks RAILS_ENV="production" LOCALE="de"
