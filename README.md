# Redmine periodictask


In some projects there are tasks that need to be assigned on a schedule. Such as check the ssl registration once per year or run security checks every 3 months



## Installation

1. `cd </path/to/redmine/dir>`
2. `git clone https://github.com/wate/redmine_periodic_task.git plugins/periodictask`
3. `bundle install`
4. `bundle exec rake redmine:plugins:migrate NAME=periodictask RAILS_ENV=production`
5. restart Redmine

After you installed the plugin you can add it as a module to a project that already exists
or activate it as default module for new projects.
On each project it will add a new tab named "Periodic Task" - just go there to add your tasks.

## Upgrade

1. `cd </path/to/redmine/dir/>plugins/periodictask`
2. `git pull`
3. `bundle install`
4. `bundle exec rake redmine:plugins:migrate NAME=periodictask RAILS_ENV=production`
5. restart Redmine

## Uninstallation

1. `cd </path/to/redmine/dir>`
2. `bundle exec rake redmine:plugins:migrate NAME=periodictask VERSION=0 RAILS_ENV=production`
3. `rm -rf plugins/periodictask`
4. restart Redmine

## Configuration

Go to your console and run `which bundle`.
In my case, that command returned `bundle`.
Use that to configure cron like this

As root do `crontab -e` and add this to the last line

```
0 1 * * * cd </path/to/redmine/dir>; bundle exec rake redmine:check_periodictasks RAILS_ENV=production
```

You can also make it run once per hour

```
0 * * * * cd </path/to/redmine/dir/>; bundle exec rake redmine:check_periodictasks RAILS_ENV=production
```

Or even every 10 minutes
```
*/10 * * * * cd </path/to/redmine/dir/>; bundle exec rake redmine:check_periodictasks RAILS_ENV=production
```

If you want to substitute variables `**DAY**`, `**WEEK**`, `**MONTH**`, `**MONTHNAME**`, `**YEAR**`, `**PREVIOUS_MONTHNAME**`, `**PREVIOUS_MONTH**` with a localized version in your laguage please add `LOCALE=ja`
(available are `de`, `en`, `ja`, `tr`, `ru`, `tr`, `zh`) to cronjob like this

```
0 * * * * cd </path/to/redmine/dir/>; bundle exec rake redmine:check_periodictasks RAILS_ENV=production LOCALE=ja
```

## Compatibility

redmine 4.1 - 5.0


## Plugins supported

redmine-periodictask supports [redminecrm checklist PRO](https://www.redmineup.com/pages/plugins/checklists) to be used when creating a periodic task.


## Authors

- [rk team](https://github.com/rkteam/) (Current maintainer)
- [jperelli](https://github.com/jperelli/Redmine-Periodic-Task) (Maintainer)
- [Tanguy de Courson](https://github.com/myneid/) (Original Author)

## Top Contributors
- [yoshiaki tanaka](https://github.com/wate)
- [yzzy](https://github.com/yzzy)
- [s-andy](https://github.com/s-andy)

## License

GNU GPLv3
