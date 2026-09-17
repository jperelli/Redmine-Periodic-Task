module RedminePeriodictask
  # The iCalendar (RFC 5545) writer: one VTODO per task, the schedule as an
  # RRULE, so calendar applications and CalDAV servers show the tasks as
  # recurring to-dos. See CalendarExport.
  #
  # DTSTART is the next run (TZID form); the end condition becomes UNTIL or,
  # without an end date, COUNT with the runs left. Tags become CATEGORIES,
  # an inactive task is a CANCELLED to-do.
  class IcalExport < CalendarExport
    FORMAT = 'ics'.freeze
    EXTENSION = 'ics'.freeze
    CONTENT_TYPE = 'text/calendar; charset=utf-8'.freeze
    PRODID = '-//Redmine Periodic Task//EN'.freeze
    CRLF = "\r\n".freeze
    LINE_OCTETS = 75
    FREQUENCIES = { 'day' => 'DAILY', 'business_day' => 'DAILY', 'week' => 'WEEKLY', 'month' => 'MONTHLY',
                    'year' => 'YEARLY' }.freeze

    def write
      lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', "PRODID:#{PRODID}", 'CALSCALE:GREGORIAN']
      @tasks.each { |task| lines.concat(todo(task)) }
      lines << 'END:VCALENDAR'
      lines.map { |line| fold(line) }.join(CRLF) + CRLF
    end

    # The recurrence rule of +task+ as an RRULE value.
    def rrule(task)
      parts = { 'FREQ' => FREQUENCIES.fetch(task.interval_units) }
      parts['INTERVAL'] = task.interval_number if task.interval_number > 1
      parts['BYDAY'] = byday(task)
      parts['WKST'] = WEEKDAYS[Periodictask.first_weekday] if task.interval_units == 'week' && task.weekdays.any?
      if task.end_date
        parts['UNTIL'] = utc(task.end_date)
      elsif task.runs_left
        parts['COUNT'] = task.runs_left
      end
      parts.compact.map { |name, value| "#{name}=#{value}" }.join(';')
    end

    private

    def todo(task)
      lines = ['BEGIN:VTODO', "UID:#{uid(task)}", "DTSTAMP:#{utc(@now)}", "DTSTART#{local(start(task))}",
               "RRULE:#{rrule(task)}", "SUMMARY:#{escape(task.subject)}"]
      lines << "DESCRIPTION:#{escape(task.description)}" if task.description.present?
      lines << "CATEGORIES:#{task.tag_names.map { |tag| escape(tag) }.join(',')}" if task.tag_names.any?
      lines << "STATUS:#{task.is_active? ? 'NEEDS-ACTION' : 'CANCELLED'}"
      lines << "URL:#{url(task)}"
      lines << 'END:VTODO'
    end

    # Weekly tasks on chosen days, business days as the working week, and
    # monthly weekday mode as ordinal weekdays ("1MO,3MO").
    def byday(task)
      case task.interval_units
      when 'business_day' then WORKDAYS.map { |wday| WEEKDAYS[wday] }.join(',')
      when 'week' then task.weekdays.map { |wday| WEEKDAYS[wday] }.join(',').presence
      when 'month'
        return unless task.monthly_weekday_mode?

        ordinal_weekdays(task).map { |ordinal, wday| "#{ordinal}#{WEEKDAYS[wday]}" }.join(',')
      end
    end

    def utc(time)
      time.utc.strftime('%Y%m%dT%H%M%SZ')
    end

    # ":20260921T030000Z" for UTC, ";TZID=Europe/Paris:20260921T050000" otherwise.
    def local(time)
      return ":#{utc(time)}" if @zone.utc_offset.zero? && @zone.tzinfo.name.match?(%r{\A(Etc/)?UTC\z})

      ";TZID=#{@zone.tzinfo.name}:#{time.strftime('%Y%m%dT%H%M%S')}"
    end

    def escape(text)
      text.to_s.gsub(/\r\n?/, "\n").gsub(/[\\;,]/) { |char| "\\#{char}" }.gsub("\n", '\n')
    end

    # Content lines longer than 75 octets continue on the next line after a
    # space, without cutting a multi-byte character.
    def fold(line)
      return line if line.bytesize <= LINE_OCTETS

      folded = []
      current = +''
      line.each_char do |char|
        if current.bytesize + char.bytesize > LINE_OCTETS - (folded.empty? ? 0 : 1)
          folded << current
          current = +''
        end
        current << char
      end
      folded << current
      folded.join("#{CRLF} ")
    end
  end
end
