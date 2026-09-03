# src/cloudflare/response.cr
module Cloudflare
  # Pagination metadata returned by list endpoints.
  struct ResultInfo
    include JSON::Serializable

    getter page        : Int32?
    getter per_page    : Int32?
    getter count       : Int32?
    getter total_count : Int32?
    getter total_pages : Int32?
  end

  # The standard Cloudflare API v4 response envelope:
  # every endpoint answers with `success`, `errors`, `messages` and `result`.
  struct Envelope
    include JSON::Serializable

    getter success  : Bool
    getter errors   : Array(ResponseError)
    getter messages : Array(ResponseError)

    # The raw `result` payload, kept as `JSON::Any` so each endpoint can
    # decode it into its own type. `nil` when the API returned `null`.
    getter result : JSON::Any?

    getter result_info : ResultInfo?

    def success? : Bool
      success
    end
  end
end
