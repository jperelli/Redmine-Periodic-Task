require 'strscan'

module RedminePeriodictask
  # The iCalendar (RFC 5545) reader: VTODO and VEVENT components with an
  # RRULE; a STATUS:CANCELLED one becomes an inactive task. See
  # CalendarImport for what is done with them.
  class IcalImport < CalendarImport
    SOURCE = 'ical'.freeze
    ACCEPT = '.ics,text/calendar'.freeze
    COMPONENTS = %w[VTODO VEVENT].freeze
    EXCEPTION_PROPERTIES = %w[EXDATE RDATE EXRULE].freeze

    private

    # Each VTODO / VEVENT as its properties, name => [[params, value], ...].
    # A file without a single component is not iCalendar at all.
    def each_entry(&)
      raise InvalidFile unless @text.match?(/^BEGIN:/i)

      components.each(&)
    end

    def rule_of(props)
      props['RRULE']&.first&.last
    end

    def rule_parts(_props, rule, _warnings)
      rule.split(';').each_with_object({}) do |part, parts|
        name, value = part.split('=', 2)
        parts[name.to_s.strip.upcase] = value.to_s.strip if name.present?
      end
    end

    def anchor_of(props, warnings)
      property_time(props, 'DTSTART', warnings) || property_time(props, 'DUE', warnings)
    end

    def uid_of(props)
      text_value(props, 'UID')
    end

    def subject_of(props)
      subject_or_default(text_value(props, 'SUMMARY'))
    end

    def description_of(props)
      text_value(props, 'DESCRIPTION')
    end

    def active?(props)
      !text_value(props, 'STATUS').to_s.strip.casecmp?('CANCELLED')
    end

    def warn_exceptions(props, warnings)
      EXCEPTION_PROPERTIES.each { |name| warn(warnings, 'part_ignored', name) if props.key?(name) }
    end

    def property_time(props, name, warnings)
      params, value = props[name]&.first
      parse_time(value, params || {}, warnings)
    end

    def text_value(props, name)
      value = props[name]&.first&.last
      return if value.nil?

      value.gsub(/\\([\\;,nN])/) { Regexp.last_match(1).casecmp?('n') ? "\n" : Regexp.last_match(1) }
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
