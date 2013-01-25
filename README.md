= periodictask =

In some projects there are tasks that need to be assigned on a schedule.
Such as check the ssl registration once per year or run security checks every 3 months

This is the redmine plugin for you if you need such a thing.
just install it, then make sure you add this to cron to run once per day

0 1 * * * cd /var/www/<redminedir>; rake redmine:check_periodictasks RAILS_ENV="production"

You can also make it run once per hour

0 * * * * cd /var/www/<redminedir>; rake redmine:check_periodictasks RAILS_ENV="production"

Or even every 10 minutes

0,10,20,30,40,50 * * * * cd /var/www/<redminedir>; rake redmine:check_periodictasks RAILS_ENV="production"

On each project it will add a new tab named Scheduled Tasks just go there to add your task

(note: this initial version is a bit rough around the edges, hopefully i will get to clean some stuff up later or maybe someone else will do it)

Make sure you run rake db:migrate_plugins as specified for installing new plugins

= Note =

Copy the files into {redmine-base-dir}/plugins/periodictask
Do not use the directory name of the repository