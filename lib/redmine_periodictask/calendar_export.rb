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
  # now.
  class CalendarExport
    WEEKDAYS = %w[SU MO TU WE TH FR SA].freeze
    WORKDAYS = [1, 2, 3, 4, 5].freeze

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
