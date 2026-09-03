# src/cloudflare/converters.cr
module Cloudflare
  # :nodoc:
  #
  # JSON converter for required RFC 3339 timestamps as returned by the
  # Cloudflare API (e.g. `"2021-01-25T18:22:34.317854Z"`).
  module TimeConverter
    extend self

    def from_json(pull : JSON::PullParser) : Time
      Time.parse_rfc3339(pull.read_string)
    end

    def to_json(value : Time, json : JSON::Builder) : Nil
      json.string(value.to_rfc3339)
    end
  end

  # :nodoc:
  #
  # JSON converter for nilable RFC 3339 timestamps. Cloudflare encodes
  # "no timestamp" as a JSON `null`.
  module NilableTimeConverter
    extend self

    def from_json(pull : JSON::PullParser) : Time?
      if pull.kind.null?
        pull.read_null
        nil
      else
        Time.parse_rfc3339(pull.read_string)
      end
    end

    def to_json(value : Time?, json : JSON::Builder) : Nil
      if value
        json.string(value.to_rfc3339)
      else
        json.null
      end
    end
  end
end
