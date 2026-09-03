# src/cloudflare/errors.cr
module Cloudflare
  # Base class for every error raised by this shard.
  class Error < Exception
  end

  # A single error entry from the Cloudflare API response envelope.
  struct ResponseError
    include JSON::Serializable

    getter code    : Int32
    getter message : String

    def to_s(io : IO) : Nil
      io << code << ' ' << message
    end
  end

  # Raised when the Cloudflare API answers with `success: false`
  # (regardless of the HTTP status code).
  class APIError < Error
    # The HTTP status code returned by the API.
    getter status_code : Int32

    # The error entries from the response envelope.
    getter errors : Array(ResponseError)

    def initialize(@status_code : Int32, @errors : Array(ResponseError) = [] of ResponseError)
      super(build_message)
    end

    private def build_message : String
      String.build do |io|
        io << "Cloudflare API request failed (HTTP " << @status_code << ')'
        unless @errors.empty?
          io << ": " << @errors.map(&.to_s).join("; ")
        end
      end
    end
  end

  # Raised when a response cannot be decoded or does not contain the
  # expected payload (e.g. a non-JSON error page from a proxy).
  class UnexpectedResponseError < Error
    # The HTTP status code, when a response was received at all.
    getter status_code : Int32?

    # The raw response body, when available.
    getter body : String?

    def initialize(message : String? = nil, *,
                   @status_code : Int32? = nil,
                   @body : String? = nil,
                   cause : Exception? = nil)
      super(message || "Unexpected response from the Cloudflare API", cause: cause)
    end
  end
end
