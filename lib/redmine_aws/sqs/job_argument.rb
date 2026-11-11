# frozen_string_literal: true

module RedmineAws
  module SQS
    # One argument of a serialized job, for JobDescription: read without
    # ActiveJob's markers, reduced to identifiers, and written for the log.
    module JobArgument
      FILTERED = '[FILTERED]'
      MAX_VALUE = 50
      # A record, as ActiveJob serializes it ({"_aj_globalid" => "gid://…"}).
      Record = Struct.new(:gid) do
        def to_s = gid
      end

      module_function

      # The value as ActiveJob serialized it, without its markers
      # ("_aj_symbol_keys", "_aj_ruby2_keywords", …), records as Record.
      def plain(value)
        case value
        when Hash
          return Record.new(value['_aj_globalid'].to_s) if value.key?('_aj_globalid')

          value.reject { |key, _| key.to_s.start_with?('_aj_') }.transform_values { |item| plain(item) }
        when Array then value.map { |item| plain(item) }
        else value
        end
      end

      # Records, numbers, true, false and nil as they are; anything else
      # filtered.
      def identifier(value)
        case value
        when Record, Integer, true, false, nil then value
        when Array then value.map { |item| identifier(item) }
        else FILTERED
        end
      end

      # Records as their GlobalID, strings quoted and cut at MAX_VALUE.
      def format(value)
        case value
        when Hash then "{#{value.map { |key, item| "#{key}: #{format(item)}" }.join(', ')}}"
        when Array then "[#{value.map { |item| format(item) }.join(', ')}]"
        when Record, FILTERED then value.to_s
        when String then value.truncate(MAX_VALUE).inspect
        else value.inspect.first(MAX_VALUE)
        end
      end
    end
  end
end
