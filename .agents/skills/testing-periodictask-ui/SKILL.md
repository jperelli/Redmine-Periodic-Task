---
name: testing-periodictask-ui
description: How to run and UI-test the Redmine Periodic Task plugin locally (docker compose), including locale checks and known non-plugin strings.
---

# Testing the Periodic Task plugin UI

## Start Redmine with the plugin
Ruby is usually not on the host; everything runs in docker.
```
docker compose build
./provision.sh                 # migrations, default data, seed project1/users/custom fields/sample tasks
docker compose up -d redmine
curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/   # wait for 200
```
Login: admin / admin at http://localhost:3000/login (Redmine may force a password change on first login).

### Schema changes in disposable local databases
- Compose bind-mounts `.volumes/sqlite`; `docker compose down -v` does not remove that host database.
- If a development migration is rewritten under an already-used version, inspect the actual schema before testing.
  For a disposable fixture database only, stop compose, preserve a backup of `.volumes/sqlite/redmine.db`,
  then move it aside and rerun provisioning/startup. Do not reset a database containing user data.
- The database file can be container-owned; use a temporary container with the same bind mount if host
  permissions prevent making the backup.

### Scheduler and REST entry points
- Manual checker UI: Administration > Plugins > Periodictask > Configure
  (`/settings/plugin/periodictask`) > Run checker now, then accept the native confirmation.
  The scheduler log reports tasks due and issues created.
- CLI checker: `docker compose exec redmine bundle exec rake redmine:check_periodictasks RAILS_ENV=development`.
- On Redmine versions with an Integrations tab, REST enablement is at
  `/settings?tab=integrations` rather than an API tab.
- The project REST collection uses the singular path `/projects/<identifier>/periodictask.json`.
  Use REST API authentication (API key or local admin basic auth), not copied browser cookies.
- The admin collection is `/admin/periodictasks` (Administration > Periodic Tasks).
  It has a subject column but no task-ID column.

### Browser evidence and Redmine conventions
- Redmine core styles `em.info` as a block field hint with normal font style. Do not
  infer an italic/inline rendering from the element name alone.
- Core `label_disabled` can render lowercase `disabled` in English. Check the
  acceptance criteria with the lead before reporting capitalization as a defect.
- For Chrome `datetime-local` fields, click each month/day/year/hour/minute segment
  and type digits. Two-digit entries may auto-advance, so an extra Right key can
  skip a segment. Verify the complete visible date/time before saving.
- For CDP full-page screenshots, discover Chrome's actual `--remote-debugging-port`
  from its running process rather than assuming port 9222; verify the capture
  helper before starting the feature recording.

## Setting up a project for periodic tasks
1. Create a project (Projects > New project) and tick the "Periodic tasks" module (`project_module_periodictask`).
2. Add a member (Settings > Members > New member) if you want to pick an assignee; the "Assignee" select is
   optional (blank = Redmine's category/project default assignee) and shows "This project has no members"
   when the project has none.
3. Index: /projects/<identifier>/periodictask ; New form: .../periodictask/new ; Detail: .../periodictask/<id>.

## Locale testing tips
- Switch language via My account > Language (http://localhost:3000/my/account). Redmine caches nothing, the
  change is immediate.
- The project tab uses `label_periodic_tasks`; the module checkbox and permission use
  `project_module_periodictask` / `permission_periodictask`. All three must exist in every locale.
- `init.rb` and `config/locales/*.yml` are loaded at boot only. After switching branches or editing them,
  run `docker compose restart redmine` (then wait for HTTP 200) or the old caption/keys keep rendering.
- Module/permission names are checked at Project > Settings (Modules fieldset) and at the permissions report
  http://localhost:3000/roles/permissions — sections are sorted alphabetically by translated name, so the
  plugin section is between "News/Noticias" and "Repository/Repositorio", not at the bottom (press End, scroll up).
- Chrome's omnibox autocompletes `localhost:3000/projects/<id>` to a previously visited deeper URL; press
  Delete before Enter to drop the suggestion.
- Tracker/status/priority names (Bug, New, Normal…) are DB data, not i18n — they stay English regardless of locale.
- To trigger `error_subtask_subject_blank`, the subtask row must have some other field set (e.g. tracker);
  a fully blank subtask row is silently dropped by `Periodictask#subtasks=`.
- To trigger `error_relation_issue_invalid`, type a non-numeric issue id (e.g. `abc`) in a relation row.
- Relations to issues in other projects fail at run time with `flash_task_run_failed` (Redmine cross-project
  relations are off by default); the main issue is still created, so you get both a success and an error flash.
- Journal titles (`label_periodictask_journal_create/run`) are visible at /projects/<id>/activity with the
  "Periodic tasks" filter ticked.
- The run-now link uses a native `confirm()` — the browser dialog shows `text_run_now_confirm`.

## Devin Secrets Needed
None (local docker, default admin/admin).

## Calendar bulk-export UI checks
- Refresh plugin assets after branch changes; if restarting alone serves stale JS,
  run `docker compose exec redmine bundle exec rake assets:precompile RAILS_ENV=development`,
  restart Redmine, and hard-reload Chrome before recording.
- Test both `/projects/<identifier>/periodictask` and `/admin/periodictasks`.
  Verify header/row checkbox synchronization and disabled zero-selection actions.
- Export twice from the same loaded page, changing checked rows between downloads.
  Redmine's POST double-submit guard can silently block repeat download forms;
  verify a new actual download rather than just an enabled menu item.
- Inspect files from Chrome's download directory, including suffixed filenames.
  Check selected UIDs, VTODO count, CRLF, text escaping, folding, recurrence and status.
- Use future-dated daily COUNT, weekly UNTIL, monthly ordinal-weekday, inactive,
  tagged and long-description fixtures, plus one unchecked control task.
- Re-import the downloaded file via the iCalendar menu. Remaining COUNT is relative
  to the exported next-run DTSTART; a count-from-import warning can be expected.
- For permission-negative POST checks use an independent session with its own login
  and CSRF token, never copied browser cookies. Python's urllib and http.cookiejar
  suffice if requests is unavailable. Assert HTTP403 and no attachment header.
- Empty-selection backend checks require native form submission because the
  normal menu intentionally blocks submitting zero checked rows.
- For multi-format exports, download JSON then crontab from the same loaded form.
  JSON uses a Group of Task entries; check weekly byDay, monthly nthOfPeriod,
  timeZone, until/count, keywords, cancelled progress and links.redmine.href.
- Crontab is intentionally lossy: interval/count/end-date/ordinal-monthly details
  are comments, inactive jobs are commented out, and imports use the next matching
  fire time rather than the original future DTSTART. Include an active monthly
  fixture to check day-of-month fallback; an inactive monthly fixture will not stage.
- Reused staging fixtures can deduplicate JSON/ICS by task UID across formats.
  Remove only disposable prior-test rows before a fresh round trip, or explicitly
  test deduplication instead. Cron loss comments survive as subject tooltips.

## Issue-template UI fixtures
- To exercise copying a non-default issue status, create the issue first, then
  use Edit to change its status. The initial New issue form may offer only New.
- Redmine can auto-watch issues created by the signed-in user. When comparing
  watcher copying, check the saved issue's Watchers list, not just the watcher
  boxes you explicitly selected while creating it.
- Keep a no-due-date fixture separate from the parent of a dated issue:
  Redmine can roll child due dates up to the parent.
- Custom fields may not be displayed on the periodic-task detail page. Reopen
  Edit after saving to verify their persisted values without changing them.
