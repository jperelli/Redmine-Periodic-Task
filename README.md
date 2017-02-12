[![Build Status](https://travis-ci.org/jperelli/Redmine-Periodic-Task.svg)](https://travis-ci.org/jperelli/Redmine-Periodic-Task)

periodictask
============

In some projects there are tasks that need to be assigned on a schedule.
Such as check the ssl registration once per year or run security checks every 3 months

After you installed the plugin you can add it as a module to a project that already exists
or activate it as default module for new projects. On each project it will add a new tab 
named "Periodic Task" - just go there to add your tasks.

Redmine version support
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
    bundle install
    bundle exec rake redmine:plugins:migrate NAME=periodictask RAILS_ENV=production
    apache2ctl graceful

Upgrade
-------

    cd /usr/local/share/redmine/plugins/periodictask
    git pull
    bundle install
    bundle exec rake redmine:plugins:migrate NAME=periodictask RAILS_ENV=production
    apache2ctl graceful

Uninstallation
--------------

    cd /usr/local/share/redmine
    bundle exec rake redmine:plugins:migrate NAME=periodictask VERSION=0 RAILS_ENV=production
    rm -rf plugins/periodictask
    apache2ctl graceful

Configuration
-------------

Go to your console and run `which bundle`. In my case, that command returned `/usr/local/rvm/gems/ruby-2.1.0/bin/bundle`. Use that to configure cron like this

As root do `crontab -e` and add this to the last line

    0 1 * * * cd /var/www/<redminedir>; /usr/local/rvm/gems/ruby-2.1.0/bin/bundle exec rake redmine:check_periodictasks RAILS_ENV="production"

You can also make it run once per hour

    0 * * * * cd /var/www/<redminedir>; /usr/local/rvm/gems/ruby-2.1.0/bin/bundle exec rake redmine:check_periodictasks RAILS_ENV="production"

Or even every 10 minutes

    */10 * * * * cd /var/www/<redminedir>; /usr/local/rvm/gems/ruby-2.1.0/bin/bundle exec rake redmine:check_periodictasks RAILS_ENV="production"

If you want to substitute variables `**DAY**`, `**WEEK**`, `**MONTH**`, `**MONTHNAME**`, `**YEAR**`, `**PREVIOUS_MONTHNAME**`, `**PREVIOUS_MONTH**` with a localized version in your laguage please add `LOCALE="de"` (available are `de`, `en`, `ja`, `tr`, `ru`, `tr`, `zh`) to cronjob like this

    0 * * * * cd /var/www/<redminedir>; /usr/local/rvm/gems/ruby-2.1.0/bin/bundle exec rake redmine:check_periodictasks RAILS_ENV="production" LOCALE="de"


Development
-----------

To help developing this plugin there is a Vagrantfile working, you can use it with VirtualBox or with [Vagrant-lxc (I recommend vagrant-lxc)](https://github.com/fgrehm/vagrant-lxc)

    vagrant plugin install vagrant-lxc
    vagrant up --provider lxc
    vagrant ssh -c "/app/redmine/bin/rails server -b0.0.0.0 -p8080"

Then go to http://192.168.2.100:8080/ and login with

    user: admin
    pass: admin

You should have a project named *project1* with `periodictask` installed

Authors
-------

  - [Julian Perelli](https://jperelli.com.ar/) (Current Mantainer)
  - [Tanguy de Courson](https://github.com/myneid/) (Original Author)

License
-------

  GNU GPLv3
