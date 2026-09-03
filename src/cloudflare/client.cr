# src/cloudflare/client.cr
module Cloudflare
  # A minimal HTTP client for the Cloudflare API v4.
  #
  # Authenticates with an API token (`Authorization: Bearer ...`) and decodes
  # the standard response envelope. Feature modules such as
  # `Cloudflare::Tunnel` build on top of it, and `Client#request` stays
  # public so endpoints that are not modeled yet can still be reached.
  #
  # ```
  # client = Cloudflare::Client.new(ENV["CLOUDFLARE_API_TOKEN"])
  # # or, reading the CLOUDFLARE_API_TOKEN environment variable:
  # client = Cloudflare::Client.from_env
  # ```
  class Client
    # Default base URL of the Cloudflare API.
    DEFAULT_BASE_URL = URI.parse("https://api.cloudflare.com")

    # Path prefix shared by all v4 endpoints.
    API_PREFIX = "/client/v4"

    getter api_token : String
    getter base_url  : URI

    def initialize(@api_token : String, *,
                   @base_url : URI = DEFAULT_BASE_URL,
                   connect_timeout : Time::Span? = nil,
                   read_timeout : Time::Span? = nil,
                   write_timeout : Time::Span? = nil)
      @http = HTTP::Client.new(@base_url)
      @http.connect_timeout = connect_timeout if connect_timeout
      @http.read_timeout = read_timeout if read_timeout
      @http.write_timeout = write_timeout if write_timeout
      @http.before_request do |request|
        request.headers["Authorization"] = "Bearer #{@api_token}"
        request.headers["Accept"] = "application/json"
        request.headers["User-Agent"] = "cloudflare.cr/#{Cloudflare::VERSION} Crystal/#{Crystal::VERSION}"
        request.headers["Content-Type"] = "application/json" if request.body
      end
    end

    # Creates a client from an API token stored in an environment variable
    # (`CLOUDFLARE_API_TOKEN` by default).
    def self.from_env(variable : String = "CLOUDFLARE_API_TOKEN") : Client
      token = ENV[variable]? ||
              raise Error.new("Environment variable #{variable} is not set")
      new(token)
    end

    def get(path : String, params : URI::Params? = nil) : Envelope
      request("GET", path, params: params)
    end

    def delete(path : String, params : URI::Params? = nil) : Envelope
      request("DELETE", path, params: params)
    end

    def post(path : String, body : String? = nil, params : URI::Params? = nil) : Envelope
      request("POST", path, params: params, body: body)
    end

    def put(path : String, body : String? = nil, params : URI::Params? = nil) : Envelope
      request("PUT", path, params: params, body: body)
    end

    def patch(path : String, body : String? = nil, params : URI::Params? = nil) : Envelope
      request("PATCH", path, params: params, body: body)
    end

    # Performs a request against the API (`path` is relative to
    # `/client/v4`, e.g. `"/accounts/#{account_id}/cfd_tunnel"`) and returns
    # the decoded `Envelope`.
    #
    # Raises `APIError` when the API answers with `success: false` and
    # `UnexpectedResponseError` when the response cannot be decoded.
    def request(method : String, path : String, *,
                params : URI::Params? = nil,
                body : String? = nil) : Envelope
      full_path = String.build do |io|
        io << API_PREFIX << path
        if params && !params.empty?
          io << '?' << params
        end
      end
      decode(@http.exec(method, full_path, body: body))
    end

    private def decode(response : HTTP::Client::Response) : Envelope
      envelope = Envelope.from_json(response.body)
      raise APIError.new(response.status_code, envelope.errors) unless envelope.success
      envelope
    rescue parse_exception : JSON::ParseException
      raise UnexpectedResponseError.new(
        "Cloudflare API returned an invalid response body",
        status_code: response.status_code,
        body: response.body,
        cause: parse_exception
      )
    end
  end
end
