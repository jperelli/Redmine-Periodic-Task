module RedminePeriodictask
  # The crontab writer: one job line per task, "m h dom mon dow  subject",
  # with the description as comment lines right above it and a blank line
  # between tasks, so CronImport reads the file back. See CalendarExport.
  #
  # Cron runs at a time of day, so minute and hour are those of the next
  # run: daily tasks are "m h * * *", business days the working week
  # ("m h * * 1,2,3,4,5"), weekly tasks the weekdays, monthly tasks the day
  # of the month of the next run and yearly tasks that day and month. What
  # cron cannot say (an interval above 1, the nth weekday of the month, the
  # end conditions, the last day of the month) is noted in comments above
  # the job; an inactive or ended task is a commented-out job.
  class CronExport < CalendarExport
    FORMAT = 'cron'.freeze
    EXTENSION = 'txt'.freeze
    CONTENT_TYPE = 'text/plain; charset=utf-8'.freeze

    def write
      lines = ["# Redmine periodic tasks, #{@now.in_time_zone(@zone).strftime('%Y-%m-%d %H:%M %Z')}",
               '# m h dom mon dow  task']
      @tasks.each do |task|
        lines << ''
        lines.concat(job(task))
      end
      "#{lines.join("\n")}\n"
    end

    # The five time fields of +task+ as a crontab schedule.
    def schedule(task)
      time = start(task)
      fields = [time.min, time.hour, '*', '*', '*']
      case task.interval_units
      when 'business_day' then fields[4] = workdays.join(',')
      when 'week' then fields[4] = (weekdays(task).presence || [time.wday]).join(',')
      when 'month' then fields[2] = time.day
      when 'year' then fields[2, 2] = [time.day, time.month]
      end
      fields.join(' ')
    end

    # The parts of the task's schedule a crontab has no field for.
    def not_carried_over(task)
      parts = []
      parts << "interval=#{task.interval_number}" if task.interval_number > 1
      parts << 'monthly_mode=weekday' if task.interval_units == 'month' && task.monthly_weekday_mode?
      parts << "end_date=#{task.end_date.in_time_zone(@zone).strftime('%Y-%m-%d')}" if task.end_date
      parts << "max_occurrences=#{task.runs_left}" if task.runs_left
      parts
    end

    private

    def notes(task)
      notes = super
      notes << I18n.t(:text_periodictask_export_month_end_cron) if month_end?(task)
      notes
    end

    def job(task)
      lines = task.description.to_s.gsub(/\r\n?/, "\n").split("\n").map { |line| comment(line) }
      lost = not_carried_over(task)
      lines << comment("#{I18n.t(:label_periodictask_import_warnings)}: #{lost.join(', ')}") if lost.any?
      notes(task).each { |note| lines << comment(note) } if recurring?(task)
      job = "#{schedule(task)}  #{command(task.subject)}"
      lines << (status(task) == :needs_action ? job : comment(job))
    end

    # The subject on one line; a % is cron's newline in a command, so it is
    # escaped as \%.
    def command(subject)
      subject.to_s.gsub(/\s+/, ' ').strip.gsub('%', '\%')
    end

    def comment(text)
      text.empty? ? '#' : "# #{text}"
    end
  end
end
