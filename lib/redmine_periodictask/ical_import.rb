require 'strscan'

module RedminePeriodictask
  # Reads the recurring items of an iCalendar file (RFC 5545: VTODO and
  # VEVENT components with an RRULE) into the subject, description and
  # schedule of a periodic task. Items without a recurrence rule are not the
  # plugin's business (they are plain issues) and are only counted.
  #
  # Recurrence rules are mapped onto what a periodic task can express:
  # FREQ/INTERVAL to the interval, BYDAY to the weekdays of a weekly task or
  # the ordinal weekdays of a monthly one, COUNT/UNTIL to the end condition,
  # DTSTART (or DUE) to the first run. Parts with no counterpart are reported
  # as warnings on the item rather than silently dropped.
  class IcalImport
    include Redmine::I18n

    Item = Struct.new(:uid, :subject, :description, :rule, :attributes, :warnings, keyword_init: true)
    Result = Struct.new(:items, :not_recurring, :unsupported, :ended, keyword_init: true)

    COMPONENTS = %w[VTODO VEVENT].freeze
    FREQUENCIES = { 'DAILY' => 'day', 'WEEKLY' => 'week', 'MONTHLY' => 'month', 'YEARLY' => 'year' }.freeze
    WEEKDAYS = { 'SU' => 0, 'MO' => 1, 'TU' => 2, 'WE' => 3, 'TH' => 4, 'FR' => 5, 'SA' => 6 }.freeze
    EXCEPTION_PROPERTIES = %w[EXDATE RDATE EXRULE].freeze

    def self.parse(text, zone: nil, now: Time.current)
      new(text, zone: zone, now: now).parse
    end

    # +zone+ is the zone floating times (no TZID, no Z) are read in: the
    # importing user's, by default the server's.
    def initialize(text, zone: nil, now: Time.current)
      @text = text.to_s
      @zone = zone || Time.zone || ActiveSupport::TimeZone['UTC']
      @now = now
    end

    def parse
      result = Result.new(items: [], not_recurring: 0, unsupported: [], ended: [])
      components.each do |props|
        rule = props['RRULE']&.first&.last
        if rule.blank?
          result.not_recurring += 1
          next
        end

        item = build_item(props, rule)
        case item
        when :unsupported then result.unsupported << subject_of(props)
        when :ended then result.ended << subject_of(props)
        else result.items << item
        end
      end
      result
    end

    private

    def build_item(props, rule)
      warnings = []
      anchor = property_time(props, 'DTSTART', warnings) || property_time(props, 'DUE', warnings)
      attributes = schedule(rule, anchor, warnings)
      return attributes if attributes.is_a?(Symbol)

      EXCEPTION_PROPERTIES.each { |name| warn(warnings, 'part_ignored', name) if props.key?(name) }
      Item.new(uid: text_value(props, 'UID').presence, subject: subject_of(props),
               description: text_value(props, 'DESCRIPTION').presence, rule: rule,
               attributes: attributes, warnings: warnings)
    end

    def subject_of(props)
      text_value(props, 'SUMMARY').to_s.strip.presence || l(:label_periodictask_import_no_subject)
    end

    # The periodic task attributes for +rule+, or :unsupported for a
    # frequency finer than daily and :ended for a rule whose UNTIL has passed.
    def schedule(rule, anchor, warnings)
      parts = rule_parts(rule)
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

    def rule_parts(rule)
      rule.split(';').each_with_object({}) do |part, parts|
        name, value = part.split('=', 2)
        parts[name.to_s.strip.upcase] = value.to_s.strip if name.present?
      end
    end

    def property_time(props, name, warnings)
      params, value = props[name]&.first
      parse_time(value, params || {}, warnings)
    end

    # DATE (20260301, the start of that day), DATE-TIME in UTC (...T090000Z),
    # with a TZID parameter, or floating (read in the import zone). An
    # unknown TZID (Windows names, for instance) falls back to the import
    # zone with a warning. Nil for a blank or malformed value.
    def parse_time(value, params, warnings)
      return if value.blank?

      match = value.strip.match(/\A(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?\z/) or return
      ymd = match[1, 3].map(&:to_i)
      hms = match[4, 3].map(&:to_i)
      return Time.utc(*ymd, *hms).in_time_zone(@zone) if match[7]

      tzid = params['TZID'].presence
      zone = tzid ? ActiveSupport::TimeZone[tzid] : @zone
      if zone.nil?
        warn(warnings, 'timezone_unknown', tzid)
        zone = @zone
      end
      zone.local(*ymd, *hms)
    rescue ArgumentError
      nil
    end

    def text_value(props, name)
      value = props[name]&.first&.last
      return if value.nil?

      value.gsub(/\\([\\;,nN])/) { Regexp.last_match(1).casecmp?('n') ? "\n" : Regexp.last_match(1) }
    end

    def warn(warnings, key, part)
      warnings << { 'key' => key, 'part' => part.to_s }
    end

    # The properties of each VTODO / VEVENT, as name => [[params, value], ...].
    # Nested components (VALARM) are skipped.
    def components
      result = []
      stack = []
      current = nil
      unfolded_lines.each do |line|
        name, params, value = split_property(line)
        next unless name

        case name
        when 'BEGIN'
          stack.push(value.upcase)
          next unless current.nil? && COMPONENTS.include?(value.upcase)

          current = { name: value.upcase, depth: stack.size, props: {} }
        when 'END'
          if current && stack.size == current[:depth] && stack.last == current[:name]
            result << current[:props]
            current = nil
          end
          stack.pop
        else
          next unless current && stack.size == current[:depth]

          (current[:props][name] ||= []) << [params, value]
        end
      end
      result
    end

    # Content lines: CRLF or LF terminated, a line starting with a space or
    # tab continues the previous one.
    def unfolded_lines
      @text.delete_prefix("\uFEFF").gsub(/\r\n?/, "\n").gsub(/\n[ \t]/, '').split("\n")
    end

    # NAME;PARAM=value;PARAM="quoted:value":value -> [NAME, {PARAM => value}, value]
    def split_property(line)
      scanner = StringScanner.new(line)
      name = scanner.scan(/[A-Za-z0-9-]+/) or return
      params = {}
      while scanner.scan(';')
        pname = scanner.scan(/[A-Za-z0-9-]+/) or return
        scanner.scan('=')
        params[pname.upcase] = scanner.scan(/(?:"[^"]*"|[^";:])*/).to_s.delete('"')
      end
      return unless scanner.scan(':')

      [name.upcase, params, scanner.rest]
    end
  end
end
