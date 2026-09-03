# Recurrence design

How a periodic task decides *when* the next issue is created, and why it works
that way. The implementation lives in `Periodictask#get_next_run_date`
(`app/models/periodictask.rb`); the scheduler in
`lib/scheduled_tasks_checker.rb` only calls that method and stores the result.

## Concepts

| Term | Meaning |
|---|---|
| `interval_number` / `interval_units` | The `Repeat every [N] [unit]` cadence. Units: `day`, `business_day`, `week`, `month`, `year`. |
| `next_run_date` | The single next occurrence stored on the task. It is also the **anchor**: it fixes the time of day, the time zone and the origin of the every-N cadence. |
| `weekdays` | JSON array of weekday numbers (`0` = Sunday .. `6` = Saturday). Used by weekly tasks and by monthly tasks in weekday mode. |
| `monthly_mode` | `day_of_month` (default) or `weekday`. Only meaningful for `month`. |
| `month_weeks` | JSON array of ordinals `1..5`: the *n*-th occurrence of each selected weekday in the month. |

The form only shows the controls that apply to the selected unit:

| Unit | Extra controls |
|---|---|
| day, business_day, year | none |
| week | seven weekday checkboxes (multiple allowed) |
| month | `day of month` / `weekday` radio; in weekday mode, ordinal checkboxes (1st..5th) and weekday checkboxes |

Options that do not apply to the selected unit/mode are cleared on save
(`clear_irrelevant_recurrence_options`), so a task switched from *week* to
*day* does not keep stale weekdays around.

## Which rule applies

```
get_next_run_date(now):
  anchor = next_run_date || now
  business_day                                  -> step anchor N business days at a time until > now
  week  and weekdays present                    -> next_weekday_occurrence
  month and monthly_mode == weekday
        and weekdays and month_weeks present    -> next_monthly_weekday_occurrence
  otherwise                                     -> anchor + k * N units  (smallest k with result > now)
```

The last branch is the pre-existing behaviour and is what every task created
before this feature uses (their `weekdays`/`month_weeks` are empty), so
existing records keep running exactly as before. It also implements monthly
*day-of-month* mode: the day is simply the anchor's day, as in Google Calendar
("Monthly on day 15" is derived from the start date, not a separate field).

## Weekly recurrence on selected weekdays

"Every N weeks on Monday and Wednesday":

1. Take the anchor's week (start of week follows Redmine's *Start calendars
   on* setting, falling back to the locale default).
2. Eligible weeks are that week plus every N-th week after it.
3. In each eligible week, candidates are the selected weekdays at the
   anchor's time of day. The first candidate that is due is the answer.

A blank first run date therefore means "the next selected weekday from now"
(possibly today), and an explicit one is used literally, even if it is not on
a selected weekday, with recurrence continuing on the selected weekdays from
that week onward.

## Monthly recurrence on the n-th weekday

"Every N months on the 1st and 3rd Monday and Wednesday":

1. Eligible months are the anchor's month plus every N-th month after it.
2. In each eligible month, candidates are the cartesian product
   `month_weeks × weekdays`, each resolved with `nth_weekday_of_month`:
   `1st, 3rd × Mon, Wed` gives 1st Mon, 1st Wed, 3rd Mon, 3rd Wed.
3. Candidates are de-duplicated and sorted; the earliest one at the
   anchor's time of day that is due is the answer.

Decisions:

- **"n-th weekday" means the n-th occurrence of that weekday**, not the
  weekday in the n-th calendar row of the month. The 1st Monday of a month
  whose 1st is a Wednesday is on the 6th.
- **A missing 5th occurrence falls back to the last one.** Months have four
  or five of each weekday; selecting *5th* means "the last one" in months
  with only four. This is how `nth_weekday_of_month` works: it computes the
  date and steps back a week while it overflows into the next month.
- **Collisions are removed.** With *4th* and *5th* both selected, a month
  with only four Mondays would otherwise yield the same date twice.
- Monthly weekday mode requires at least one ordinal and one weekday
  (`validate_recurrence`); the other modes have no extra validation.

## Anchor, time of day and time zone

- All candidates are built with `anchor.change(year:, month:, day:)`, i.e.
  the anchor's wall-clock time in the anchor's zone. A task set to 10:00
  keeps running at 10:00 across DST changes and no matter how late the
  scheduler runs.
- Occurrences are derived from the anchor and never from `now`, so a
  scheduler that runs at 10:04 does not drift the task to 10:04.
- `due?` is strict (`> now`) when a `next_run_date` exists, because that
  date has just run, and inclusive (`>= now`) when it is blank, so a blank
  first run created on a matching day at a matching time can run "now".

## First run date

- **Explicit**: it is the literal first run and the anchor. It does not have
  to satisfy the recurrence rule; later occurrences do.
- **Blank**: the current time is the anchor and the first run is the next
  occurrence that matches the rule. The controller assigns the submitted
  recurrence options *before* computing this, and blanks it again if
  validation fails so the user is not shown a computed date they never
  entered.

## Catch-up after downtime

If the scheduler was not running for a while, a task creates **one** issue
and then advances to the next *future* occurrence. Missed occurrences are
not back-filled. This is the pre-existing behaviour and applies to all
units; `each_eligible_period` starts iterating close to `now` so a long
downtime does not walk through every skipped period.

## Storage and compatibility

- `weekdays` and `month_weeks` are JSON columns, following the existing
  `subtasks`/`relations` pattern; values are normalised on read and write
  (integers only, within range, unique, sorted), so malformed or duplicated
  form input cannot produce bad schedules.
- Only the single earliest `next_run_date` is stored. There is no second
  scheduler or expansion table; the scheduler's query and update loop is
  unchanged.
- Running the migration adds the three nullable columns; no data migration
  is needed.

## Human-readable schedule

Index and detail pages share `periodictask_schedule_description`
(`app/helpers/periodictask_helper.rb`), so they cannot diverge. It uses
pluralised locale keys:

```
each day                     every 3 business days
each week on Monday, Wednesday   every 2 weeks on Monday, Wednesday
each month on day 15         each month on the 1st, 3rd Monday, Wednesday
every 6 months on day 3      each year
```

Weekday names are listed in the configured start-of-week order.
