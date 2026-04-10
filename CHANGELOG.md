# Changelog

## v6.1.2 - 2026-04-10

### Fixes

- fix Custom Fields aren't read from the DB ([#131](https://github.com/jperelli/Redmine-Periodic-Task/issues/131)) (@jperelli)

### Chores

- Add bulgarian translation ([#132](https://github.com/jperelli/Redmine-Periodic-Task/pull/132)) (@jwalkerbg)

## v6.1.1 - 2026-04-07

### Fixes

- Migration fails for mysql watcher_user_ids json default value ([#130](https://github.com/jperelli/Redmine-Periodic-Task/issues/130)) (@jperelli)

## v6.1.0 - 2026-04-07

> warning: This version requires migrations to be run. Remember to run:
> bundle exec rake redmine:plugins:migrate NAME=periodictask RAILS_ENV=production

### Features

- Using timezones other than UTC is now possible ([#25](https://github.com/jperelli/Redmine-Periodic-Task/issues/25)) (@jperelli)
- Add parent task support ([#107](https://github.com/jperelli/Redmine-Periodic-Task/issues/107), [#108](https://github.com/jperelli/Redmine-Periodic-Task/issues/108), [#116](https://github.com/jperelli/Redmine-Periodic-Task/issues/116))  (@jperelli)
- Add QUARTER variable to use in subject and description ([#101](https://github.com/jperelli/Redmine-Periodic-Task/issues/101)) (@jperelli)
- Add WEEKISO variable to use in subject and description ([#92](https://github.com/jperelli/Redmine-Periodic-Task/issues/92)) (@jperelli)
- Add field priority to periodic tasks ([#56](https://github.com/jperelli/Redmine-Periodic-Task/issues/56), [#127](https://github.com/jperelli/Redmine-Periodic-Task/issues/127)) (@jperelli)
- Add field watchers to periodic tasks ([#52](https://github.com/jperelli/Redmine-Periodic-Task/issues/52)) (@jperelli)

### Fixes

- Next run date constantly increasing ([#79](https://github.com/jperelli/Redmine-Periodic-Task/issues/79))
- PREVIOUS_MONTH variable not working correctly ([#118](https://github.com/jperelli/Redmine-Periodic-Task/issues/118), [#126](https://github.com/jperelli/Redmine-Periodic-Task/issues/126))
- Compatibility with redmine 6.1, attr_protected issue ([#129](https://github.com/jperelli/Redmine-Periodic-Task/issues/129))

### Chores

- Code formatted with RuboCop (@jperelli)
- Add plugin tests (@jperelli)
- Add github CI configuration to run tests on each commit (@jperelli)
- Update README.md and add badge (@jperelli)
- Add CHANGELOG.md (@jperelli)
- Improve all locales (@jperelli)
- Add translation for portuguese (@jperelli)
- Add translation for croatian ([#123](https://github.com/jperelli/Redmine-Periodic-Task/issues/123)) (@jperelli)
- Add translation for polish ([#77](https://github.com/jperelli/Redmine-Periodic-Task/issues/77)) (@jperelli)
- Add translation for ukranian (@jperelli)

## v6.0.0 - 2025-01-11

### Features

- Upgraded to be used with redmine 6 (@jperelli)

## v5.0.0 - 2024-04-24

### Features

- Upgraded to be used with redmine 5 (@jperelli)
  
### Chores

- Update README.md (@jperelli)
- Update ru.yml (@oleg-kolzhanov)

## v4.1.0 - 2019-03-04

### Features

- Support issue custom fields (#16) (@s-andy)
- Save issue creation errors to show them in UI later (@s-andy)

### Fixes

- Delete periodic tasks when their project is destroyed (#76) (@s-andy)
- Eliminate duplicate loading of Rails environment (@yzzy)
- Fix Gemfile (@s-andy)

### Chores

- Update ja.yml (@tatsuyaueda)
- Decrease Codacy complexity (@yzzy)
- Redmine 4.0-stable for Travis CI (@yzzy)
- Some model refactoring (@yzzy)
- Restore Redmine v2 compatibility (@yzzy)

## v4.0.0 - 2019-01-15

### Features

- Quick'n'dirty fix for Redmine v4 compatibility (@yzzy)

### Fixes

- Rake task email notifying fixed (@yzzy)
  
### Chores

- Change support table for master branch (@jperelli)
- Travis CI config (@yzzy)
- Remove Gemfile.lock (@yzzy)
- fixing port-number in README (klemens)

## v3.3.1 - 2018-09-25

### Fixes

- Fixed compatibility with RedmineUP Checklist plugin (light version) (@yzzy)

## v3.3.0 - 2018-09-11

### Features

- fix #49 Add Estimated Time field (@jperelli)

### Fixes

- fix #83 support for redmineUP checklists plugin (@jperelli)
- Fix bug with issues without descriptions (@alexandermeindl)
- Remove gem file version, because this version blocks other redmine plugins to use other versions (@alexandermeindl)
- Fixed delete confirmation message in list view (@alexandermeindl)
- fixed html error in form template (@alexandermeindl)
- fixed interval_number bug (@alexandermeindl)
- Bang added to issue.save! (@davidegiacometti)

### Chores

- Italian translation added (@davidegiacometti)
- spelling fix (klemens)
- add info for donating (@jperelli)

## v3.2.1 - 2017-02-18

### Chores

- Fixes #62 add locales for labels: author, tracker (@jperelli)

## v3.2.0 - 2017-02-12

### Features

- Fixes #57 add suport for DAY variable (@jperelli)
- Add '**PREVIOUS_MONTH**'. (@msysh)

### Fixes

- Fixes #48, disabling possibility to save interval=0, never try to divide by zero! (@jperelli)
- Save Time.now in a variable, to use always the same value (@jperelli)
- Fixes #55 Interval without weekend days (@jperelli)
- Fix typo (@jperelli)

### Chores

- Add locale 'ja'. (@msysh)
- Create zh.yml (@tomora)
- Removing print that wasn't needed (@jperelli)
- Update rvm version (@jperelli)
- Adding a Vagrantfile with provisioner to rapid develop without having redmine installed (@jperelli)
- Redmine version in README description (@jperelli)
- Remove not needed file (@jperelli)
- Add source to Gemfile to work on travis (@jperelli)

## v3.1.2 - 2016-01-06

### Features

- Add previous monthname to variable output (to complete #36) (@mape2k)
  
### Fixes

- Copy subject/description before replacing variables. Otherwise variables will be also replaced in task. (@mape2k)

### Chores

- Update README.md (@jperelli)

## v3.1.1 - 2015-10-27

### Features

- Previous month and variables in description (@jperelli)

### Fixes

- wrong label (@jperelli)

### Chores

- Create ru.yml (@jperelli)
- Comment minor modification (@jperelli)
- Fixes #32 error in cron documentation (@jperelli)

## v3.1.0 - 2015-10-07

### Features

- Add issue category to periodic tasks (Urs Joss)

### Chores

- Localization Create tr.yml (@atopcu)
- refs #27 trying to fix the fixture failure (@jperelli)
- refs #27 remove the Engines var (@jperelli)
- refs #27 changing path to test_helper (@jperelli)
- refs #27 matching plugin name (@jperelli)
- refs #27 trying to get travis to work (@jperelli)

## v3.0.3 - 2015-09-15

### Fixes

- Fix for issue #23 (@jperelli)

## v3.0.2 - 2015-06-17

### Fixes

- fix: delete a periodic task (@marczona)

## v3.0.1 - 2015-06-11

### Features

- Allow assigning to groups and fix some typos (@mape2k)
  
## v3.0.0 - 2015-05-13

### Features

- Support redmine 3, preserving compatibility with redmine 2 (@s2chmich)
- Allow to add creation date as start date (@mape2k)
- Allow to add due date dependent on start date (@mape2k)
- Allow to add description to new tickets (@mape2k)
- Allow to use date-related information for subject using variables (@mape2k)

### Fixes

- Fixes #14: migration not working for postgres (@jperelli)
- Calculate new run date based on old run date not on current time (@mape2k)
- fixes #6 (@jperelli)
- Fixes #5 (@jperelli)

### Chores

- localization improvements (@cforce, @mape2k)
- Readme updates (@jperelli)

## v2.0.0 - 2013-01-25

### Features

- Initial support for redmine 2 (@jperelli)

## v1.0.1 - 2013-01-24

### Features

- Completed support to use datetime scheduling as well as the date (@jperelli)

### Chores

- Created Module (@csfreak)

## v1.0.0 - 2011-10-18

### Fixes

- fixes #3 remove the stupid find_by_sql (@myneid)
- fixes #1 updating a periodic task actually updates it WOW! (@myneid)

### Chores

- cleaning up a bit and removing vim temp files (@myneid)
- small change in readme (@myneid)

## v0.1.0 - 2011-09-26

### Features

- Initial version (@myneid)
