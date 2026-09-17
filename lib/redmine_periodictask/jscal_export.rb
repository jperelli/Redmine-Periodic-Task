require 'json'

module RedminePeriodictask
  # The JSCalendar (RFC 8984) writer: a Group whose entries are one Task
  # per periodic task, the schedule as a RecurrenceRule (the RRULE of
  # IcalExport as JSON: "frequency": "weekly", "byDay": [{"day": "mo"}],
  # ...). See CalendarExport.
  #
  # start and until are LocalDateTime values in the entry's timeZone; the
  # end condition becomes until or, without an end date, count with the
  # runs left. Tags become keywords, an inactive task has progress
  # "cancelled".
  class JscalExport < CalendarExport
    FORMAT = 'jscal'.freeze
    EXTENSION = 'json'.freeze
    CONTENT_TYPE = 'application/jscalendar+json; charset=utf-8'.freeze
    PRODID = IcalExport::PRODID
    FREQUENCIES = { 'day' => 'daily', 'business_day' => 'daily', 'week' => 'weekly', 'month' => 'monthly',
                    'year' => 'yearly' }.freeze

    def write
      group = { '@type' => 'Group', 'uid' => "periodictasks-#{@now.to_i}@#{host}", 'prodId' => PRODID,
                'updated' => utc(@now), 'title' => 'Redmine periodic tasks',
                'entries' => @tasks.map { |task| entry(task) } }
      "#{JSON.pretty_generate(group)}\n"
    end

    # The recurrence rule of +task+ as a RecurrenceRule object.
    def recurrence_rule(task)
      rule = { '@type' => 'RecurrenceRule', 'frequency' => FREQUENCIES.fetch(task.interval_units) }
      rule['interval'] = task.interval_number if task.interval_number > 1
      days = by_day(task)
      rule['byDay'] = days if days
      rule['firstDayOfWeek'] = day_code(Periodictask.first_weekday) if task.interval_units == 'week' && days
      if task.end_date
        rule['until'] = local(task.end_date.in_time_zone(@zone))
      elsif task.runs_left
        rule['count'] = task.runs_left
      end
      rule
    end

    private

    def entry(task)
      entry = { '@type' => 'Task', 'uid' => uid(task), 'updated' => utc(@now), 'title' => task.subject.to_s }
      entry['description'] = task.description if task.description.present?
      entry['start'] = local(start(task))
      entry['timeZone'] = @zone.tzinfo.name
      entry['recurrenceRules'] = [recurrence_rule(task)]
      entry['keywords'] = task.tag_names.to_h { |tag| [tag, true] } if task.tag_names.any?
      entry['progress'] = task.is_active? ? 'needs-action' : 'cancelled'
      entry['links'] = { 'redmine' => { '@type' => 'Link', 'href' => url(task), 'rel' => 'alternate' } }
      entry
    end

    # Weekly tasks on chosen days, business days as the working week, and
    # monthly weekday mode as NDay objects with nthOfPeriod.
    def by_day(task)
      case task.interval_units
      when 'business_day' then WORKDAYS.map { |wday| nday(wday) }
      when 'week' then task.weekdays.map { |wday| nday(wday) }.presence
      when 'month'
        return unless task.monthly_weekday_mode?

        ordinal_weekdays(task).map { |ordinal, wday| nday(wday, ordinal) }
      end
    end

    def nday(wday, ordinal = nil)
      { '@type' => 'NDay', 'day' => day_code(wday), 'nthOfPeriod' => ordinal }.compact
    end

    def day_code(wday)
      WEEKDAYS[wday].downcase
    end

    def utc(time)
      time.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
    end

    def local(time)
      time.strftime('%Y-%m-%dT%H:%M:%S')
    end
  end
end
