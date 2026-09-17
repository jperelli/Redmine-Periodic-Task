module RedminePeriodictask
  # What the bulk "Export to ..." actions of the task lists write: the
  # checked periodic tasks as a file another program reads, one format per
  # subclass, named by its FORMAT and listed in .exporters: iCalendar
  # (IcalExport), JSCalendar (JscalExport) and crontab (CronExport). Each
  # is the inverse of the importer of the same format: what is exported
  # reads back as the same schedule.
  #
  # Times are written in +zone+ (the user's), so the weekday and the day of
  # the month are the ones the user sees; a task without a next run starts
  # now. The plugin evaluates the schedule in the application's zone, so
  # when the two zones put the start on different dates the weekdays of a
  # weekly task are shifted along (see #weekdays).
  #
  # A task that has ended (all its runs done, or its next run past the end
  # date) is written without a recurrence, as a completed item.
  #
  # What a recurrence rule cannot say exactly is still written as the
  # closest rule, with a note for the reader (see #notes): every N business
  # days, which the plugin counts over working days only.
  class CalendarExport
    WEEKDAYS = %w[SU MO TU WE TH FR SA].freeze

    # The formats that can be exported, in menu order.
    def self.exporters
      [IcalExport, JscalExport, CronExport]
    end

    def self.for_format(format)
      exporters.find { |exporter| format == exporter::FORMAT }
    end

    def self.export(tasks, zone:, now: Time.current)
      new(tasks, zone: zone, now: now).write
    end

    def initialize(tasks, zone:, now: Time.current)
      @tasks = tasks
      @zone = zone || ActiveSupport::TimeZone['UTC']
      @now = now
    end

    # The file contents.
    def write
      raise NotImplementedError
    end

    def self.filename(name)
      "periodictasks-#{name}.#{self::EXTENSION}"
    end

    private

    def start(task)
      (task.next_run_date || @now).in_time_zone(@zone)
    end

    # The start as the plugin sees it, in the application's zone.
    def anchor(task)
      task.next_run_date || @now
    end

    # The weekdays of a weekly task as seen in +zone+: a run on Wednesday
    # 01:00 UTC is on Tuesday 22:00 in Buenos Aires, so Wednesday becomes
    # Tuesday there.
    def weekdays(task)
      shift = (start(task).to_date - anchor(task).to_date).to_i
      task.weekdays.map { |wday| (wday + shift) % 7 }.sort
    end

    def recurring?(task)
      !task.ended?
    end

    # A monthly task on the 31st: the last day of the month (BYMONTHDAY=-1)
    # rather than a day shorter months skip.
    def month_end?(task)
      task.interval_units == 'month' && !task.monthly_weekday_mode? && anchor(task).day == 31
    end

    # Sentences for the reader about what the written rule only
    # approximates.
    def notes(task)
      notes = []
      if task.interval_units == 'business_day' && task.interval_number > 1
        notes << I18n.t(:text_periodictask_export_business_day_interval, count: task.interval_number)
      end
      notes
    end

    # :needs_action, :cancelled (switched off) or :completed (ended).
    def status(task)
      if !task.is_active?
        :cancelled
      elsif task.ended?
        :completed
      else
        :needs_action
      end
    end

    # The end condition the format gets, [:until, end_date] or
    # [:count, runs_left]; nil when the task is unlimited. A rule takes one
    # of the two, so with both set it is the one that stops the task first:
    # the runs left, unless the end date cuts them short.
    def end_condition(task)
      runs = task.runs_left
      date = task.end_date
      return [:count, runs] if runs && (date.nil? || task.upcoming_run_dates_through(date, @now, runs).size >= runs)

      [:until, date] if date
    end

    # The wdays of the working week, per Redmine's non-working days setting.
    def workdays
      @workdays ||= begin
        working_days = Periodictask.working_days
        sunday = @now.to_date - @now.to_date.wday
        (0..6).select { |wday| working_days.working_day?(sunday + wday) }
      end
    end

    def uid(task)
      "periodictask-#{task.id}@#{host}"
    end

    def url(task)
      "#{Setting.protocol}://#{Setting.host_name}/projects/#{task.project.identifier}/periodictask/#{task.id}"
    end

    def host
      Setting.host_name.to_s.split('/').first.presence || 'redmine'
    end

    # The [ordinal, wday] pairs of a monthly task in weekday mode: the 1st
    # and 3rd Monday as [[1, 1], [3, 1]]; the fifth, which the plugin
    # resolves to the last one, as -1.
    def ordinal_weekdays(task)
      task.month_weeks.product(task.weekdays).map { |ordinal, wday| [ordinal == 5 ? -1 : ordinal, wday] }
    end
  end
end
