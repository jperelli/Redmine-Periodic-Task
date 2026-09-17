require 'digest/sha1'

module RedminePeriodictask
  # The crontab reader: each job line of a user crontab (minute, hour, day
  # of month, month, day of week, command) or @daily-style shortcut becomes
  # an item whose subject is the command and whose description is the
  # comment lines right above it. Environment lines (MAILTO=...) are
  # skipped. See CalendarImport for what is done with the items.
  #
  # A job that runs more than once a day (several minutes or hours, or *
  # in either) is reported as unsupported. Otherwise the day fields pick
  # the frequency: no restriction is daily, a day-of-week list is weekly,
  # a day-of-month list is monthly (the first day; the others are
  # reported), and a month list on top of that is yearly. Cron has no
  # start date, so the first run is the next time the job would run.
  class CronImport < CalendarImport
    SOURCE = 'cron'.freeze
    ACCEPT = '.cron,.crontab,.txt,text/plain'.freeze
    SHORTCUTS = { '@yearly' => '0 0 1 1 *', '@annually' => '0 0 1 1 *', '@monthly' => '0 0 1 * *',
                  '@weekly' => '0 0 * * 0', '@daily' => '0 0 * * *', '@midnight' => '0 0 * * *',
                  '@hourly' => '0 * * * *' }.freeze
    RANGES = [0..59, 0..23, 1..31, 1..12, 0..7].freeze
    MONTH_NAMES = %w[jan feb mar apr may jun jul aug sep oct nov dec].freeze
    DAY_NAMES = %w[sun mon tue wed thu fri sat].freeze
    # Field index => the names its values may be written as, and the value of the first name.
    NAMES = { 3 => [MONTH_NAMES, 1], 4 => [DAY_NAMES, 0] }.freeze
    SUBJECT_LENGTH = 255
    # How far ahead the first run is looked for (a day of month that never
    # comes, like 31 with month 2, is left without one).
    HORIZON_DAYS = 366 * 8

    # A job line. +fields+ are the five time fields as sorted arrays of
    # integers, nil for an unrestricted (*) field; nil altogether for
    # @reboot, which does not repeat.
    Job = Struct.new(:rule, :fields, :command, :comments, keyword_init: true)

    private

    def each_entry
      comments = []
      @text.each_line do |raw|
        line = raw.strip
        if line.empty? || env_line?(line)
          comments = []
        elsif line.start_with?('#')
          comments << line.sub(/\A#\s?/, '')
        else
          yield job_of(line, comments)
          comments = []
        end
      end
    end

    def env_line?(line)
      line.match?(/\A[A-Za-z_][A-Za-z0-9_]*\s*=/)
    end

    # Any line that is not blank, a comment or an environment setting has
    # to be a job, as in cron itself; anything else is not a crontab.
    def job_of(line, comments)
      if line.start_with?('@')
        keyword, command = line.split(/\s+/, 2)
        keyword = keyword.downcase
        return Job.new(rule: nil, fields: nil, command: command, comments: comments) if keyword == '@reboot'

        rule = SHORTCUTS[keyword] or raise InvalidFile
        Job.new(rule: keyword, fields: parse_fields(rule.split), command: command, comments: comments)
      else
        tokens = line.split(/\s+/, 6)
        raise InvalidFile if tokens.size < 6

        Job.new(rule: tokens[0, 5].join(' '), fields: parse_fields(tokens[0, 5]), command: tokens[5],
                comments: comments)
      end
    end

    def parse_fields(tokens)
      tokens.each_with_index.map { |token, index| parse_field(token, index) }
    end

    # "1,15", "1-5", "*/2", "mon-fri", "*" (nil: no restriction). Sunday
    # is 0 or 7.
    def parse_field(token, index)
      return if token == '*'

      range = RANGES[index]
      values = token.split(',').flat_map { |item| parse_item(item, index, range) }
      values.map! { |value| value == 7 ? 0 : value } if index == 4
      values.uniq.sort
    end

    def parse_item(item, index, range)
      match = item.match(%r{\A(\*|[a-z0-9]+)(?:-([a-z0-9]+))?(?:/(\d+))?\z}i) or raise InvalidFile
      raise InvalidFile if match[1] == '*' && match[2]

      first = match[1] == '*' ? range.first : value_of(match[1], index, range)
      last = if match[2]
               value_of(match[2], index, range)
             else
               match[1] == '*' ? range.last : first
             end
      step = match[3] ? match[3].to_i : 1
      raise InvalidFile if step < 1 || first > last

      (first..last).step(step).to_a
    end

    def value_of(token, index, range)
      value = if token.match?(/\A\d+\z/)
                token.to_i
              elsif (names, first = NAMES[index]) && (position = names.index(token.downcase))
                first + position
              end
      raise InvalidFile unless value && range.cover?(value)

      value
    end

    def rule_of(job)
      job.rule
    end

    def once_a_day?(job)
      minute, hour = job.fields
      minute&.one? && hour&.one?
    end

    # The frequency the day fields amount to and the parts left over, or
    # a sub-daily frequency (reported as unsupported) for a job running
    # several times a day.
    def rule_parts(job, _rule, warnings)
      return { 'FREQ' => 'HOURLY' } unless once_a_day?(job)

      _minute, _hour, dom, mon, dow = job.fields
      parts = {}
      if dom.nil? && dow.nil?
        parts['FREQ'] = 'DAILY'
        parts['BYMONTH'] = mon.join(',') if mon
      elsif dom.nil?
        parts['FREQ'] = 'WEEKLY'
        parts['BYDAY'] = dow.map { |wday| DAY_NAMES[wday].upcase[0, 2] }.join(',')
        parts['BYMONTH'] = mon.join(',') if mon
      elsif mon.nil?
        parts['FREQ'] = 'MONTHLY'
        parts['BYMONTHDAY'] = dom.join(',')
      else
        parts['FREQ'] = 'YEARLY'
        parts['BYMONTHDAY'] = dom.drop(1).join(',') if dom.many?
        parts['BYMONTH'] = mon.drop(1).join(',') if mon.many?
      end
      warn(warnings, 'part_ignored', "dow=#{dow.join(',')}") if dom && dow
      parts
    end

    # The next time the job runs, in the import zone: today or the next
    # day it runs on at its hour and minute.
    def anchor_of(job, _warnings)
      return unless once_a_day?(job)

      minute, hour = job.fields
      today = @now.in_time_zone(@zone).to_date
      first = @zone.local(today.year, today.month, today.day, hour.first, minute.first)
      today += 1 if first <= @now
      HORIZON_DAYS.times do |offset|
        day = today + offset
        return @zone.local(day.year, day.month, day.day, hour.first, minute.first) if runs_on?(job, day)
      end
      nil
    end

    # Whether the periodic task the job maps to runs on +day+: only its
    # first day of month (and month) count, as rule_parts reports the rest.
    def runs_on?(job, day)
      _minute, _hour, dom, mon, dow = job.fields
      return true if dom.nil? && dow.nil?
      return dow.include?(day.wday) if dom.nil?

      day.day == dom.first && (mon.nil? || day.month == mon.first)
    end

    def uid_of(job)
      "cron:#{Digest::SHA1.hexdigest("#{job.rule} #{job.command}")}"
    end

    def subject_of(job)
      subject_or_default(job.command.to_s.truncate(SUBJECT_LENGTH))
    end

    # The comments above the job; a command too long for the subject is
    # kept whole here.
    def description_of(job)
      lines = job.comments.dup
      lines.unshift(job.command) if job.command.to_s.length > SUBJECT_LENGTH
      lines.join("\n")
    end
  end
end
