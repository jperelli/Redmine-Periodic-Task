# Redmine periodictask [![Test](https://github.com/jperelli/Redmine-Periodic-Task/actions/workflows/test.yml/badge.svg)](https://github.com/jperelli/Redmine-Periodic-Task/actions/workflows/test.yml)

In some projects there are tasks that need to be assigned on a schedule. Such as check the ssl registration once per year or run security checks every 3 months

After you installed the plugin you can add it as a module to a project that already exists or activate it as default module for new projects. On each project it will add a new tab named "Periodic Task" - just go there to add your tasks.

## Redmine version support

Support for old redmine versions has been dropped.
If you are using an old version, you can use the corresponding branch according to the following table.
If you cannot migrate to a newer version and still need support, you can hire me to do it. Just contact me with the details.

<table>
  <tr>
    <td rowspan="2">git branch</td>
    <td colspan="6">redmine version support</td>
  </tr>
  <tr>
    <td>1.x</td>
    <td>2.x</td>
    <td>3.x</td>
    <td>4.x</td>
    <td>5.x</td>
    <td>6.x</td>
  </tr>
  <tr>
    <td>main</td>
    <td>?</td>
    <td>?</td>
    <td>?</td>
    <td>?</td>
    <td>✅</td>
    <td>✅</td>
  </tr>
  <tr>
    <td>redmine4</td>
    <td>?</td>
    <td>?</td>
    <td>✅</td>
    <td>✅</td>
    <td>🚫</td>
    <td>🚫</td>
  </tr>
  <tr>
    <td>redmine2</td>
    <td>✅</td>
    <td>✅</td>
    <td>🚫</td>
    <td>🚫</td>
    <td>🚫</td>
    <td>🚫</td>
  </tr>
</table>

To use redmine2 branch, when cloning use `-b redmine2` like this `git clone -b redmine2 http://github.com:/jperelli/Redmine-Periodic-Task.git plugins/periodictask`

## Installation

    cd /usr/local/share/redmine
    git clone http://github.com:/jperelli/Redmine-Periodic-Task.git plugins/periodictask
    bundle install
    bundle exec rake redmine:plugins:migrate NAME=periodictask RAILS_ENV=production
    apache2ctl graceful

## Upgrade

    cd /usr/local/share/redmine/plugins/periodictask
    git pull
    bundle install
    bundle exec rake redmine:plugins:migrate NAME=periodictask RAILS_ENV=production
    apache2ctl graceful

## Uninstallation

    cd /usr/local/share/redmine
    bundle exec rake redmine:plugins:migrate NAME=periodictask VERSION=0 RAILS_ENV=production
    rm -rf plugins/periodictask
    apache2ctl graceful

## Configuration

Go to your console and run `which bundle`. In my case, that command returned `/usr/local/rvm/gems/ruby-2.1.0/bin/bundle`. Use that to configure cron like this

As root do `crontab -e` and add this to the last line

    0 1 * * * cd /var/www/<redminedir>; /usr/local/rvm/gems/ruby-2.1.0/bin/bundle exec rake redmine:check_periodictasks RAILS_ENV="production"

You can also make it run once per hour

    0 * * * * cd /var/www/<redminedir>; /usr/local/rvm/gems/ruby-2.1.0/bin/bundle exec rake redmine:check_periodictasks RAILS_ENV="production"

Or even every 10 minutes

    */10 * * * * cd /var/www/<redminedir>; /usr/local/rvm/gems/ruby-2.1.0/bin/bundle exec rake redmine:check_periodictasks RAILS_ENV="production"

### Variable interpolation

You can use the following variables in the subject and description of a periodic task. They will be replaced with the corresponding value when the issue is created.

| Variable | Description |
|---|---|
| `**DAY**` | Day of the month, zero-padded (01..31) |
| `**WEEK**` | Week number of the year, starting with the first Monday as the first day of the first week (00..53) |
| `**WEEKISO**` | ISO 8601 week number of the year (01..53) |
| `**MONTH**` | Month of the year, zero-padded (01..12) |
| `**MONTHNAME**` | Full month name (e.g. January), localized |
| `**QUARTER**` | Quarter of the year (1..4) |
| `**YEAR**` | Four-digit year |
| `**PREVIOUS_MONTH**` | Previous month, zero-padded (01..12) |
| `**PREVIOUS_MONTHNAME**` | Full name of the previous month, localized |

If you want to get localized month names, please add `LOCALE="de"` (available are `de`, `en`, `ja`, `tr`, `ru`, `tr`, `zh`) to cronjob like this

    0 * * * * cd /var/www/<redminedir>; /usr/local/rvm/gems/ruby-2.1.0/bin/bundle exec rake redmine:check_periodictasks RAILS_ENV="production" LOCALE="de"

## Plugins supported

redmine-periodictask supports [redminecrm checklist PRO](https://www.redmineup.com/pages/plugins/checklists) to be used when creating a periodic task.

## Development

Start with `docker compose up --build` and wait until it finishes.
In other console do `./provision.sh`, this will install initial data for it to be easier to develop.

Then go to http://127.0.0.1:3000/ and login with

    user: admin
    pass: admin

You should have a project named *project1* with `periodictask` installed

In order to run the "cron checker": `docker compose exec redmine bundle exec rake redmine:check_periodictasks RAILS_ENV=development`

## Authors

  - [Julian Perelli](https://jperelli.com.ar/) (Current Maintainer)
  - [Tanguy de Courson](https://github.com/myneid/) (Original Author)

## Top Contributors

 - [yzzy](https://github.com/yzzy)
 - [s-andy](https://github.com/s-andy)
 - [tuzumkuru](https://github.com/tuzumkuru) redmine v6 support

## License

MIT
