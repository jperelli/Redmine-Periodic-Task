module RedminePeriodictask
  # The crontab writer: one job line per task, "m h dom mon dow  subject",
  # with the description as comment lines right above it and a blank line
  # between tasks, so CronImport reads the file back. See CalendarExport.
  #
  # Cron runs at a time of day, so minute and hour are those of the next
  # run: daily tasks are "m h * * *", business days "m h * * 1-5", weekly
  # tasks the weekdays, monthly tasks the day of the month of the next run
  # and yearly tasks that day and month. What cron cannot say (an interval
  # above 1, the nth weekday of the month, an end condition) is noted in a
  # comment above the job; an inactive task is a commented-out job.
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
      when 'business_day' then fields[4] = '1-5'
      when 'week' then fields[4] = (task.weekdays.presence || [time.wday]).join(',')
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
      parts << "max_occurrences=#{task.runs_left}" if task.runs_left && !task.end_date
      parts
    end

    private

    def job(task)
      lines = task.description.to_s.gsub(/\r\n?/, "\n").split("\n").map { |line| comment(line) }
      lost = not_carried_over(task)
      lines << comment("#{I18n.t(:label_periodictask_import_warnings)}: #{lost.join(', ')}") if lost.any?
      job = "#{schedule(task)}  #{task.subject.to_s.gsub(/\s+/, ' ').strip}"
      lines << (task.is_active? ? job : comment(job))
    end

    def comment(text)
      text.empty? ? '#' : "# #{text}"
    end
  end
end
