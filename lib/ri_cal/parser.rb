module RiCal

  PARAM_SINGLE_VALUE_REGEXP = /"[^"]*"[^";:,]*|[^";:,]*/
  PARAM_VALUE_REGEXP = /#{PARAM_SINGLE_VALUE_REGEXP}(?:,#{PARAM_SINGLE_VALUE_REGEXP})*/
  PARAM_REGEXP = /([a-zA-Z\-0-9_]+)=(#{PARAM_VALUE_REGEXP})/

  #- ©2009 Rick DeNatale
  #- All rights reserved. Refer to the file README.txt for the license
  #
  class Parser # :nodoc:
    attr_reader :last_line_str #:nodoc:
    def next_line #:nodoc:
      result = nil
      begin
        result = buffer_or_line
        @buffer = nil
        state = :outside
        state = check_state(state, result)
        while (m = buffer_or_line.match(/^\s/)) || state == :inside
          if m
            @buffer = @buffer[1..-1]
          else
            @buffer = "\n" + @buffer
          end
          state &&= check_state(state, @buffer)
          result = "#{result}#{@buffer}"
          @buffer = nil
        end
        result
      rescue EOFError
        result
      end
    end

    def check_state(state, buffer)
      buffer.scan(/[\"\:]/) do |char|
        if char == ':'
          return nil if state == :outside
        else
          state = state == :inside ? :outside : :inside
        end
      end
      state
    end
    private :check_state

    def self.parse_params(string) #:nodoc:
      if string
        if string == ""
          {}
        elsif string =~ /\A#{PARAM_REGEXP}(?:;#{PARAM_REGEXP})*\z/
          string.scan(PARAM_REGEXP).inject({}) { |result, (key, val)|
            # Just remove the quotes as they are not allowed in both quoted and unquoted values
            param_val = val.gsub(/"/, '')
            param_val = param_val.gsub(/&quot;/, '"').gsub(/&apos;/, "'").gsub(/&amp;/, "&").gsub(/&#([0-9]+);/) { $1.to_i.chr }
            result[key] = param_val
            result
          }
        else
          raise "Invalid parameters #{string.inspect}"
        end
      else
        nil
      end
    end

    def self.params_and_value(string, optional_initial_semi = false) #:nodoc:
      string = string.sub(/^:/,'')
      return [{}, string] unless optional_initial_semi || string.match(/^;/)
      segments = string.sub(';','').split(":", -1)
      return [{}, string] if segments.length < 2
      quote_count = 0
      gathering_params = true
      params = []
      values = []
      segments.each do |segment|
        if gathering_params
          params << segment
          quote_count += segment.count("\"")
          gathering_params = (1 == quote_count % 2)
        else
          values << segment
        end
      end
      [parse_params(params.join(":")), values.join(":")]
    end

    def separate_line(string) #:nodoc:
      match = string.match(/^([^;:]*)(.*)$/m)
      name = match[1]
      @last_line_str = string
      params, value = *Parser.params_and_value(match[2])
      {
        :name => name,
        :params => params,
        :value => value,
      }
    end

    def next_separated_line #:nodoc:
      line = next_line
      line ? separate_line(line) : nil
    end

    def buffer_or_line #:nodoc:
      @buffer ||= @io.readline.chomp
    end

    def initialize(io = StringIO.new("")) #:nodoc:
      @io = io
    end

    def self.parse(io = StringIO.new("")) #:nodoc:
      new(io).parse
    end

    def invalid #:nodoc:
      raise Exception.new("Invalid icalendar file")
    end

    def still_in(component, separated_line) #:nodoc:
      invalid unless separated_line
      separated_line[:value] != component || separated_line[:name] != "END"
    end

    def parse #:nodoc:
      result = []
      while start_line = next_line
        @parent_stack = []
        component = parse_one(start_line, nil)
        result << component if component
      end
      result
    end

    # TODO: Need to parse non-standard component types (iana-token or x-name)
    def parse_one(start, parent_component) #:nodoc:

      @parent_stack << parent_component
      if Hash === start
        first_line = start
      else
        first_line = separate_line(start)
      end
      invalid unless first_line[:name] == "BEGIN"
      entity_name = first_line[:value]
      result = case entity_name
      when "VCALENDAR"
        RiCal::Component::Calendar.from_parser(self, parent_component, entity_name)
      when "VEVENT"
        RiCal::Component::Event.from_parser(self, parent_component, entity_name)
      when "VTODO"
        RiCal::Component::Todo.from_parser(self, parent_component, entity_name)
      when "VJOURNAL"
        RiCal::Component::Journal.from_parser(self, parent_component, entity_name)
      when "VFREEBUSY"
        RiCal::Component::Freebusy.from_parser(self, parent_component, entity_name)
      when "VTIMEZONE"
        RiCal::Component::Timezone.from_parser(self, parent_component, entity_name)
      when "VALARM"
        RiCal::Component::Alarm.from_parser(self, parent_component, entity_name)
      when "DAYLIGHT"
        RiCal::Component::Timezone::DaylightPeriod.from_parser(self, parent_component, entity_name)
      when "STANDARD"
        RiCal::Component::Timezone::StandardPeriod.from_parser(self, parent_component, entity_name)
      else
        RiCal::Component::NonStandard.from_parser(self, parent_component, entity_name)
      end
      @parent_stack.pop
      result
    end
  end
end
