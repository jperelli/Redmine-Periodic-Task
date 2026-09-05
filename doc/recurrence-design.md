# Recurrence design

This document explains how a periodic task decides when the next issue is
created. The code is in `Periodictask#get_next_run_date`
(`app/models/periodictask.rb`). The scheduler in
`lib/scheduled_tasks_checker.rb` calls that method and stores the result.

## Fields

| Field | Meaning |
|---|---|
| `interval_number`, `interval_units` | The `Repeat every [N] [unit]` setting. Units are `day`, `business_day`, `week`, `month` and `year`. |
| `next_run_date` | The next time the task runs. It is also the anchor: it sets the time of day, the time zone and the starting point for the every-N count. |
| `weekdays` | JSON array of weekday numbers, `0` is Sunday and `6` is Saturday. Used by weekly tasks and by monthly tasks in weekday mode. |
| `monthly_mode` | `day_of_month` (default) or `weekday`. Only used when the unit is `month`. |
| `month_weeks` | JSON array of ordinals from `1` to `5`. `3` means the third occurrence of each selected weekday in the month. |

The form shows extra controls only for some units:

| Unit | Extra controls |
|---|---|
| day, business_day, year | none |
| week | seven weekday checkboxes, more than one can be checked |
| month | a `day of month` / `weekday` radio; in weekday mode, ordinal checkboxes (1st to 5th) and weekday checkboxes |

When a task is saved, options that do not apply to its unit and mode are
cleared (`clear_irrelevant_recurrence_options`). A task that is changed from
week to day does not keep its old weekdays.

## Which rule is used

```
get_next_run_date(now):
  anchor = next_run_date || now
  business_day                                  -> next_business_day_occurrence
  week, with weekdays selected                  -> next_weekday_occurrence
  month, monthly_mode == weekday,
        with weekdays and month_weeks selected  -> next_monthly_weekday_occurrence
  anything else                                 -> anchor + k * N units, smallest k that is after now
```

The last rule is the old behaviour. Every task created before this feature
has empty `weekdays` and `month_weeks`, so it keeps using this rule and runs
as before. The same rule handles the monthly day-of-month mode: the day is
the day of the anchor. Google Calendar works the same way, "Monthly on day
15" comes from the start date and there is no separate field for it.

## Business days

Example: every 3 business days.

Only the date is walked: N business days are added to the date of the anchor
until the result is after now, and the time of day of the anchor is kept. The
`business_time` gem counts from an instant, so counting from the anchor itself
would move a task scheduled outside business hours to the start of a business
day (09:00 by default) and, for an evening task, skip the next day: 20:30 on a
Monday first rolls forward to Tuesday 09:00 and then adds the interval.
Weekends and the gem's holidays are skipped either way.

## Weekly, on selected weekdays

Example: every 2 weeks on Monday and Wednesday.

1. Start from the week of the anchor. The first day of the week follows the
   Redmine setting "Start calendars on", or the locale default when that is
   not set.
2. The task can run in that week and in every N-th week after it.
3. In each of those weeks, the candidates are the selected weekdays at the
   time of day of the anchor. The first candidate after now is the result.

With a blank first run date, the first run is the next selected weekday,
which can be today. With an explicit first run date, that date is used as
is, even when it is not on a selected weekday. Later runs follow the
selected weekdays, counting weeks from the week of that date.

## Monthly, on the n-th weekday

Example: every month on the 1st and 3rd Monday and Wednesday.

1. The task can run in the month of the anchor and in every N-th month
   after it.
2. In each of those months, every ordinal is combined with every weekday.
   `1st, 3rd` and `Mon, Wed` give the 1st Monday, 1st Wednesday, 3rd Monday
   and 3rd Wednesday. Each pair is turned into a date by
   `nth_weekday_of_month`.
3. Duplicate dates are removed, the dates are sorted, and the first one
   after now, at the time of day of the anchor, is the result.

Details:

- "3rd Monday" means the third Monday of the month, not the Monday of the
  third week. When the 1st of the month is a Wednesday, the 1st Monday is
  on the 6th.
- Some months have five of a weekday and some have four. When `5th` is
  selected and the month has only four, the fourth one is used, so `5th`
  behaves as "last". `nth_weekday_of_month` computes the date and moves it
  back a week while it falls into the next month.
- Duplicates are removed because `4th` and `5th` can point to the same date
  in a month with four of that weekday.
- In weekday mode at least one ordinal and one weekday must be selected
  (`validate_recurrence`). The other modes need no extra validation.

## Time of day and time zone

Every candidate date is built with `anchor.change(year:, month:, day:)`.
This keeps the wall-clock time and the time zone of the anchor. A task set
for 10:00 runs at 10:00 after a DST change, and it still runs at 10:00 when
the scheduler is late.

Candidates are computed from the anchor, not from now. A scheduler that runs
at 10:04 does not move the task to 10:04.

`due?` compares a candidate with now. When the task has a `next_run_date`,
that date has already run, so the candidate must be later than now. When the
first run date is blank, the candidate may be equal to now, so a task created
on a matching day and time can run right away.

## First run date

With an explicit first run date, that date is the first run and the anchor.
It does not need to match the recurrence rule. Later runs do.

With a blank first run date, the current time is the anchor and the first run
is the next time that matches the rule. The controller assigns the submitted
recurrence options before it computes this date. If validation fails, the
computed date is cleared again so the form does not show a date the user
never typed.

## Missed runs

When the scheduler was down for a while, a task creates one issue and then
moves to the next run in the future. Missed runs are not created one by one.
This is the old behaviour and it applies to all units.
`each_eligible_period` starts counting close to now, so a long downtime does
not loop over every skipped week or month.

## Storage and compatibility

- `weekdays` and `month_weeks` are JSON columns, like the existing `subtasks`
  and `relations` columns. Values are normalised when read and when written:
  only integers, only values in range, no duplicates, sorted. Bad or repeated
  form input cannot produce a bad schedule.
- Only one `next_run_date` is stored, the earliest one. There is no second
  scheduler and no table of future runs. The scheduler query and update loop
  did not change.
- The migration adds three nullable columns. No data migration is needed.

## Schedule text

The list and the detail page both use `periodictask_schedule_description`
in `app/helpers/periodictask_helper.rb`, so they always show the same text.
The text uses pluralised locale keys. Examples:

```
each day                          every 3 business days
each week on Monday, Wednesday    every 2 weeks on Monday, Wednesday
each month on day 15              each month on the 1st, 3rd Monday, Wednesday
every 6 months on day 3           each year
```

Weekday names are listed in the order set by "Start calendars on".
