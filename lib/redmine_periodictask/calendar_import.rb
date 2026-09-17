module RedminePeriodictask
  # Reads the recurring items of a calendar (or crontab) file into the subject,
  # description and schedule of a periodic task. Each format is read by a
  # subclass, named by its SOURCE and listed in .importers: iCalendar
  # (IcalImport, RFC 5545), JSCalendar (JscalImport, RFC 8984) and crontab
  # (CronImport). Items without a recurrence rule are not the plugin's
  # business (they are plain issues) and are only counted.
  #
  # Recurrence is described in the vocabulary of RFC 5545 (RRULE parts:
  # FREQ, INTERVAL, BYDAY, UNTIL, ...): subclasses turn a rule into a parts
  # hash and the mapping onto what a periodic task can express lives here:
  # FREQ/INTERVAL to the interval, BYDAY to the weekdays
  # of a weekly task or the ordinal weekdays of a monthly one, COUNT/UNTIL
  # to the end condition, the item's start (or due date) to the first run.
  # Parts with no counterpart are reported as warnings on the item rather
  # than silently dropped.
  class CalendarImport
    include Redmine::I18n

    # The file is not in the importer's format.
    class InvalidFile < StandardError; end

    Item = Struct.new(:uid, :subject, :description, :rule, :attributes, :warnings, keyword_init: true)
    Result = Struct.new(:items, :not_recurring, :unsupported, :ended, keyword_init: true)

    FREQUENCIES = { 'DAILY' => 'day', 'WEEKLY' => 'week', 'MONTHLY' => 'month', 'YEARLY' => 'year' }.freeze
    WEEKDAYS = { 'SU' => 0, 'MO' => 1, 'TU' => 2, 'WE' => 3, 'TH' => 4, 'FR' => 5, 'SA' => 6 }.freeze

    # The formats that can be imported, in menu order. Each has a SOURCE
    # (stored with the staged rows) and an ACCEPT (for the file picker).
    def self.importers
      [IcalImport, JscalImport, CronImport]
    end

    def self.for_source(source)
      importers.find { |importer| source == importer::SOURCE }
    end

    def self.parse(text, zone: nil, now: Time.current)
      new(text, zone: zone, now: now).parse
    end

    # +zone+ is the zone floating times (no time zone of their own) are read
    # in: the importing user's, by default the server's.
    def initialize(text, zone: nil, now: Time.current)
      @text = text.to_s
      @zone = zone || Time.zone || ActiveSupport::TimeZone['UTC']
      @now = now
    end

    # Goes through each_entry, sorting entries into staged items, counted
    # non-recurring ones, and skipped unsupported / ended ones.
    def parse
      result = Result.new(items: [], not_recurring: 0, unsupported: [], ended: [])
      each_entry do |entry|
        rule = rule_of(entry)
        if rule.blank?
          result.not_recurring += 1
          next
        end

        item = build_item(entry, rule)
        case item
        when :unsupported then result.unsupported << subject_of(entry)
        when :ended then result.ended << subject_of(entry)
        else result.items << item
        end
      end
      result
    end

    private

    # Subclasses: yield each to-do / event of the file.
    def each_entry
      raise NotImplementedError
    end

    # Subclasses: the recurrence rule of +entry+ (any object; blank when
    # there is none).
    def rule_of(entry)
      raise NotImplementedError
    end

    # Subclasses: the RRULE parts of +rule+ as
    # { 'FREQ' => 'WEEKLY', 'BYDAY' => 'MO,TU', ... }, UNTIL as an iCalendar
    # UTC date-time (20260301T090000Z). +warnings+ collects what could not
    # be expressed as a part.
    def rule_parts(entry, rule, warnings)
      raise NotImplementedError
    end

    # Subclasses: the item's first run (Time or nil), uid, subject and
    # description.
    def anchor_of(entry, warnings)
      raise NotImplementedError
    end

    def uid_of(entry)
      raise NotImplementedError
    end

    def subject_of(entry)
      raise NotImplementedError
    end

    def description_of(entry)
      raise NotImplementedError
    end

    # The rule as shown to the user.
    def rule_text(rule)
      rule.to_s
    end

    # Subclasses: warn about what +entry+ carries besides its rule that has
    # no counterpart (excluded dates, extra dates, overrides, more rules).
    def warn_exceptions(entry, warnings); end

    def build_item(entry, rule)
      warnings = []
      anchor = anchor_of(entry, warnings)
      attributes = schedule(rule_parts(entry, rule, warnings), anchor, warnings)
      return attributes if attributes.is_a?(Symbol)

      warn_exceptions(entry, warnings)
      Item.new(uid: uid_of(entry).presence, subject: subject_of(entry),
               description: description_of(entry).presence, rule: rule_text(rule),
               attributes: attributes, warnings: warnings)
    end

    def subject_or_default(subject)
      subject.to_s.strip.presence || l(:label_periodictask_import_no_subject)
    end

    # The periodic task attributes for the rule +parts+, or :unsupported for
    # a frequency finer than daily and :ended for a rule whose UNTIL has
    # passed. +parts+ is consumed.
    def schedule(parts, anchor, warnings)
      units = FREQUENCIES[parts.delete('FREQ').to_s.upcase]
      return :unsupported unless units

      attributes = { 'interval_number' => [parts.delete('INTERVAL').to_i, 1].max, 'interval_units' => units,
                     'weekdays' => [], 'month_weeks' => [], 'monthly_mode' => nil }
      end_date = parse_time(parts.delete('UNTIL'), {}, warnings)
      return :ended if end_date && end_date <= @now

      attributes['end_date'] = end_date&.iso8601
      count = parts.delete('COUNT').to_i
      if count.positive?
        attributes['max_occurrences'] = count
        warn(warnings, 'count_from_import', "COUNT=#{count}")
      end
      parts.delete('WKST')

      byday = parse_byday(parts.delete('BYDAY'))
      bysetpos = parts.delete('BYSETPOS')
      bymonthday = parts.delete('BYMONTHDAY')
      anchor = apply_by_parts(attributes, units, anchor, byday, bysetpos, bymonthday, warnings)
      attributes['next_run_date'] = anchor&.iso8601
      parts.each { |name, value| warn(warnings, 'part_ignored', "#{name}=#{value}") }
      attributes
    end

    # Applies BYDAY / BYSETPOS / BYMONTHDAY to +attributes+ per frequency and
    # returns the (possibly moved) anchor.
    def apply_by_parts(attributes, units, anchor, byday, bysetpos, bymonthday, warnings)
      case units
      when 'day'
        if byday.any? && attributes['interval_number'] == 1
          attributes['interval_units'] = 'week'
          attributes['weekdays'] = byday.map(&:last).uniq.sort
        elsif byday.any?
          warn(warnings, 'part_ignored', "BYDAY=#{byday.map(&:first).join(',')}")
        end
      when 'week'
        attributes['weekdays'] = byday.map(&:last).uniq.sort
      when 'month'
        if byday.any?
          bysetpos = apply_monthly_byday(attributes, byday, bysetpos, warnings)
        elsif bymonthday
          anchor = apply_bymonthday(anchor, bymonthday, warnings)
          bymonthday = nil
        end
      else
        warn(warnings, 'part_ignored', "BYDAY=#{byday.map(&:first).join(',')}") if byday.any?
      end
      warn(warnings, 'part_ignored', "BYSETPOS=#{bysetpos}") if bysetpos
      warn(warnings, 'part_ignored', "BYMONTHDAY=#{bymonthday}") if bymonthday
      anchor
    end

    # "1MO,3MO" (or "MO" with BYSETPOS=1,3) becomes the 1st and 3rd Monday;
    # -1 is the last one, which the plugin expresses as the 5th (or last).
    # A plain "MO" is every Monday of the month. Returns the BYSETPOS left
    # unused, for the caller to report.
    def apply_monthly_byday(attributes, byday, bysetpos, warnings)
      ordinals = byday.filter_map { |raw, _wday| [raw[/\A[+-]?\d+/]&.to_i, "BYDAY=#{raw}"] if raw =~ /\A[+-]?\d/ }
      if ordinals.empty? && bysetpos
        ordinals = bysetpos.split(',').map { |n| [n.to_i, "BYSETPOS=#{n}"] }
        bysetpos = nil
      end
      month_weeks = ordinals.filter_map do |n, part|
        n = 5 if n == -1
        next n if Periodictask::MONTH_WEEKS.include?(n)

        warn(warnings, 'part_ignored', part)
        nil
      end
      attributes['monthly_mode'] = 'weekday'
      attributes['month_weeks'] = ordinals.empty? ? Periodictask::MONTH_WEEKS.dup : month_weeks.uniq.sort
      attributes['weekdays'] = byday.map(&:last).uniq.sort
      bysetpos
    end

    # A monthly task runs on the day of the month of its anchor, so the
    # anchor moves to the first BYMONTHDAY; further days and counting from
    # the end of the month (-1) have no counterpart.
    def apply_bymonthday(anchor, bymonthday, warnings)
      days = bymonthday.split(',').map(&:to_i)
      day = days.shift
      days.each { |d| warn(warnings, 'part_ignored', "BYMONTHDAY=#{d}") }
      unless day.between?(1, 28) || (anchor && day.between?(29, anchor.end_of_month.day))
        warn(warnings, 'part_ignored', "BYMONTHDAY=#{day}")
        return anchor
      end
      return anchor if anchor.nil? || anchor.day == day

      warn(warnings, 'monthday_moved', "BYMONTHDAY=#{day}")
      anchor.change(day: day)
    end

    # [[raw, wday], ...] for "1MO,-1FR,TU"; unknown day codes are dropped.
    def parse_byday(value)
      value.to_s.split(',').filter_map do |raw|
        raw = raw.strip.upcase
        wday = WEEKDAYS[raw[/[A-Z]{2}\z/]]
        [raw, wday] if wday
      end
    end

    # An iCalendar DATE (20260301, the start of that day), DATE-TIME in UTC
    # (...T090000Z), with a TZID parameter, or floating (read in the import
    # zone). An unknown TZID (Windows names, for instance) falls back to the
    # import zone with a warning. Nil for a blank or malformed value.
    def parse_time(value, params, warnings)
      return if value.blank?

      match = value.strip.match(/\A(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?\z/) or return
      ymd = match[1, 3].map(&:to_i)
      hms = match[4, 3].map(&:to_i)
      return Time.utc(*ymd, *hms).in_time_zone(@zone) if match[7]

      zone_named(params['TZID'], warnings).local(*ymd, *hms)
    rescue ArgumentError
      nil
    end

    # The zone called +name+, or the import zone when there is no name; an
    # unknown name falls back to the import zone with a warning.
    def zone_named(name, warnings)
      return @zone if name.blank?

      ActiveSupport::TimeZone[name] || begin
        warn(warnings, 'timezone_unknown', name)
        @zone
      end
    end

    def warn(warnings, key, part)
      warning = { 'key' => key, 'part' => part.to_s }
      warnings << warning unless warnings.include?(warning)
    end
  end
end
