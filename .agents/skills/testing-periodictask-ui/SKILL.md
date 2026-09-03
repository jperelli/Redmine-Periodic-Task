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

## Setting up a project for periodic tasks
1. Create a project (Projects > New project) and tick the "Periodic tasks" module (`project_module_periodictask`).
2. Add a member (Settings > Members > New member) — the form's required "Assignee" select is empty and the
   task cannot be created until the project has at least one member.
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
