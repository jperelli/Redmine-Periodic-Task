require 'json'

module RedminePeriodictask
  # The JSCalendar (RFC 8984) reader: Task and Event objects with
  # recurrenceRules, on their own, in a Group or in a JSON array. See
  # CalendarImport for what is done with them. A cancelled one (a Task
  # with progress "cancelled", an Event with status "cancelled") becomes
  # an inactive task.
  #
  # A RecurrenceRule is the RRULE of RFC 5545 as a JSON object, so it is
  # turned back into RRULE parts (frequency "weekly" to FREQ=WEEKLY, byDay
  # [{day: "mo", nthOfPeriod: 2}] to BYDAY=2MO, ...) and mapped like an
  # iCalendar rule.
  class JscalImport < CalendarImport
    SOURCE = 'jscal'.freeze
    ACCEPT = '.json,.jscal,application/jscalendar+json,application/json'.freeze
    ENTRY_TYPES = %w[Event Task].freeze
    # RecurrenceRule property => RRULE part, for the list-valued ones.
    LIST_PARTS = { 'byMonthDay' => 'BYMONTHDAY', 'bySetPosition' => 'BYSETPOS', 'byMonth' => 'BYMONTH',
                   'byYearDay' => 'BYYEARDAY', 'byWeekNo' => 'BYWEEKNO', 'byHour' => 'BYHOUR',
                   'byMinute' => 'BYMINUTE', 'bySecond' => 'BYSECOND' }.freeze
    # Properties an entry may carry beyond its first rule, none of which a
    # periodic task can express.
    EXCEPTION_PROPERTIES = %w[excludedRecurrenceRules recurrenceOverrides].freeze

    private

    # Each Task / Event object of the file, wherever it sits: at the top
    # level, in the entries of a Group, or in an array of either.
    def each_entry(&)
      root = JSON.parse(@text)
      raise InvalidFile unless root.is_a?(Hash) || root.is_a?(Array)

      walk(root, &)
    rescue JSON::ParserError
      raise InvalidFile
    end

    def walk(node, &)
      case node
      when Array
        node.each { |child| walk(child, &) }
      when Hash
        if node['entries'].is_a?(Array)
          walk(node['entries'], &)
        elsif entry?(node)
          yield node
        end
      end
    end

    # A typed Task / Event, or an untyped object that looks like one.
    def entry?(node)
      type = node['@type']
      type ? ENTRY_TYPES.include?(type) : (node.key?('uid') || node.key?('title'))
    end

    def rule_of(entry)
      rules = entry['recurrenceRules']
      rules.first if rules.is_a?(Array) && rules.first.is_a?(Hash)
    end

    def rule_parts(entry, rule, warnings)
      parts = {}
      rule.each do |name, value|
        case name
        when '@type' then next
        when 'frequency' then parts['FREQ'] = value.to_s.upcase
        when 'interval' then parts['INTERVAL'] = value.to_s
        when 'count' then parts['COUNT'] = value.to_s
        when 'until' then parts['UNTIL'] = until_part(entry, value, warnings)
        when 'byDay' then parts['BYDAY'] = byday_part(value)
        when 'firstDayOfWeek' then parts['WKST'] = value.to_s.upcase
        when 'rscale' then parts['RSCALE'] = value.to_s unless value.to_s.casecmp?('gregorian')
        when 'skip' then parts['SKIP'] = value.to_s unless value.to_s.casecmp?('omit')
        else parts[LIST_PARTS[name] || name.to_s.upcase] = value.is_a?(Array) ? value.join(',') : value.to_s
        end
      end
      parts.compact
    end

    # until is a LocalDateTime in the entry's zone; as an RRULE part it has
    # to be in UTC.
    def until_part(entry, value, warnings)
      time = local_time(value, entry, warnings)
      time&.utc&.strftime('%Y%m%dT%H%M%SZ')
    end

    # [{"day": "mo", "nthOfPeriod": 2}, {"day": "fr"}] -> "2MO,FR"
    def byday_part(value)
      return unless value.is_a?(Array)

      value.filter_map { |nday| "#{nday['nthOfPeriod']}#{nday['day'].to_s.upcase}" if nday.is_a?(Hash) }.join(',')
    end

    def anchor_of(entry, warnings)
      local_time(entry['start'], entry, warnings) || local_time(entry['due'], entry, warnings)
    end

    def uid_of(entry)
      entry['uid'].to_s
    end

    def subject_of(entry)
      subject_or_default(entry['title'])
    end

    def description_of(entry)
      entry['description'].to_s
    end

    def active?(entry)
      !(entry['progress'].to_s.casecmp?('cancelled') || entry['status'].to_s.casecmp?('cancelled'))
    end

    def rule_text(rule)
      rule.except('@type').to_json
    end

    def warn_exceptions(entry, warnings)
      extra = entry['recurrenceRules'].size - 1
      warn(warnings, 'part_ignored', "recurrenceRules[1..#{extra}]") if extra.positive?
      EXCEPTION_PROPERTIES.each { |name| warn(warnings, 'part_ignored', name) if entry[name].present? }
    end

    # A LocalDateTime (2026-03-01T09:00:00, no offset) read in the entry's
    # timeZone, or in the import zone when it has none (floating). A date
    # alone is the start of that day; a trailing Z is read as UTC. Nil for a
    # blank or malformed value or an unknown time zone.
    def local_time(value, entry, warnings)
      return if value.blank?

      match = value.to_s.strip.match(/\A(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?(Z)?)?\z/)
      return unless match

      ymd = match[1, 3].map(&:to_i)
      hms = match[4, 3].map(&:to_i)
      return Time.utc(*ymd, *hms).in_time_zone(@zone) if match[7]

      zone_named(entry['timeZone'], warnings).local(*ymd, *hms)
    rescue ArgumentError
      nil
    end
  end
end
