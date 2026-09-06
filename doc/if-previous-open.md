# If the previous issue is still open

Every periodic task has a setting called *Previous issue open*. It decides
what a due run does when the issue created by the previous run has not been
closed yet. "Previous issue" means the newest top-level issue
the task generated (subtasks generated with it do not count); an issue that
was deleted from Redmine is ignored. The setting is copied with the task and
shown on its detail page. *Run now* ignores it and always creates an issue.

| Mode | In one line |
|---|---|
| [Create a new issue anyway](#create-a-new-issue-anyway) | Default. A new issue is created every time, whatever happened to the old one. |
| [Skip this occurrence](#skip-this-occurrence) | Nothing is created this time; the schedule moves on as if it had. |
| [Close the previous issue](#close-the-previous-issue) | The old issue is closed, then the new one is created. |
| [Wait until it is closed](#wait-until-it-is-closed) | Nothing is created and the schedule pauses; it restarts from the day the old issue is closed. |

The first three keep the fixed calendar of the task (see
[recurrence-design.md](recurrence-design.md)); only the last one changes when
the next issue is due.

## Create a new issue anyway

**A new issue is created on every occurrence, even if the previous one is
still open.**

This is the default and the behaviour the plugin always had. The task does
not look at what happened to the issues it created before: every time the
next run date arrives, a new issue is created and the next run date moves to
the following occurrence. Open issues from earlier occurrences stay open until
somebody deals with them. Use it when each occurrence is a separate piece of
work that must be tracked even if the previous one is late, or when several
people work on different occurrences in parallel.

Examples:

- A daily "Check the backups" task. Monday's issue was never closed. On
  Tuesday a new issue is created anyway and both are open.
- A monthly invoice task creates one issue per month. In June the May issue
  is still open because the customer has not paid: June's issue is created
  and both invoices are visible in the issue list.

## Skip this occurrence

**If the previous issue is still open, nothing is created this time and the
next run date moves on to the next occurrence.**

The task keeps its fixed calendar but does not create a duplicate while the
previous issue is open. The skipped occurrence is lost: when the issue is
finally closed, the next issue appears at the next regular date, not
immediately. The skip is not an error: *Last error* stays empty. Instead the
task detail page shows *The run of … did not create an issue: #123 was still
open* above the list of generated issues, and the scheduler log
(*Administration → Plugins → Redmine periodictask → Configure*) records
`skipped: #123 is still open` in its *Notes* column. Use it when only one
open instance of the issue makes sense, and missing an occurrence is
acceptable: recurring reminders, housekeeping chores, "review the open pull
requests".

Examples:

- A weekly "Write the status report" task runs on Mondays. Nobody closes the
  issue of Monday the 1st. On the 8th nothing is created and the note is
  recorded; the same on the 15th. The issue is closed on Wednesday the 17th.
  The next issue is created on Monday the 22nd, the regular slot.
- A daily "Water the plants" task. The issue is left open for three days:
  three occurrences are skipped, then the issue is closed and the next one is
  created the following morning as usual.

## Close the previous issue

**The previous issue is closed and the new one is created.**

The plugin closes the previous issue (and the subtasks it generated under
it) with the first closed status that the workflow allows the task's author
to set, or, failing that, the tracker's first closed status, or any closed
status. A journal note *Closed by the periodic task: superseded by #124* is
added so the history explains what happened. Then the new issue is created
and the next run date moves on as usual. If Redmine refuses to close the old
issue (it is blocked by another issue, it has open subtasks the task did not
create, or there is no closed status at all) the new issue is still created
and the failure is shown in *Last error* and in the scheduler log. Use it
when the newest occurrence replaces the older ones, so that an old issue
nobody will ever act on does not stay open forever.

Examples:

- A daily "Today's stand-up notes" task. Yesterday's issue is still open at
  09:00: it is closed with the note *superseded by #457* and today's issue
  #457 is created.
- A weekly "Update the dependencies" task. Last week's issue is still open
  but it is blocked by another issue: the new issue is created, the old one
  stays open, and *Last error* on the task shows *Could not close the previous
  issue: #440: …* until the next successful run.

## Wait until it is closed

**Nothing is created while the previous issue is open, and the next issue is
due one interval after the day it is closed.**

This is the "repeat after completion" of Todoist (`every!`), Asana or
ClickUp. While the previous issue is open, the task creates nothing and its
next run date does not move: the task stays due, the detail page shows the
*did not create an issue: #123 was still open* note and the scheduler log
records it. Once the issue is closed, the schedule restarts from the closing
day: the next run is the first occurrence after that day, at the task's usual
time of day and following its rules (business days, selected weekdays, n-th
weekday of the month, time zone). If that date is already in the past, for
example because the issue was closed long ago while the scheduler was down,
the issue is created right away. The scheduler log records *#123 was closed,
next run rescheduled to …*. Use it for work that should happen a fixed time
after the previous time it was done, rather than on fixed dates: "change the
filter 30 days after the last time", "call the customer two weeks after the
last call".

Examples:

- A task set to every 30 days at 10:00 (*Replace the water filter*). The
  issue is created on March 1st and closed on March 12th at 15:37: the next
  issue is due 30 days later, on April 11th at 10:00, whatever the original
  calendar said. Left open for two months, nothing else is created meanwhile.
- A daily task at 10:00. Yesterday's issue is closed this morning at 09:00:
  the next one is due tomorrow at 10:00, not today at 10:00.
- A task every 2 weeks. The issue is closed on Wednesday the 9th: the next
  issue is due on Wednesday the 23rd.
- A weekly task on Mondays and Wednesdays. The issue is closed on a Tuesday:
  the next issue is due on Wednesday, the first selected weekday after the
  closing day.
- A task every business day. The issue is closed on a Friday: the next issue
  is due on Monday.

How the date is calculated is described in
[recurrence-design.md](recurrence-design.md#previous-issue-still-open).
