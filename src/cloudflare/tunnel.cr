# src/cloudflare/tunnel.cr
require "base64"
require "random/secure"

module Cloudflare
  # Cloudflare Tunnel API (cloudflared / Zero Trust tunnels).
  #
  # Maps the `cfd_tunnel` endpoints of the Cloudflare API v4:
  # https://developers.cloudflare.com/api/resources/zero_trust/subresources/tunnels/
  #
  # ```
  # client = Cloudflare::Client.from_env
  # account_id = "699d98642c564d2e855e9661899b7252"
  #
  # # Create a remotely-managed tunnel and grab its token:
  # tunnel = Cloudflare::Tunnel.create(client, account_id, "my-tunnel",
  #   config_src: Cloudflare::Tunnel::ConfigSrc::Cloudflare)
  # token = Cloudflare::Tunnel.token(client, account_id, tunnel.id)
  #
  # # Publish an application through it:
  # config = Cloudflare::Tunnel::Config.new([
  #   Cloudflare::Tunnel::IngressRule.new("http://localhost:8080", hostname: "app.example.com"),
  #   Cloudflare::Tunnel::IngressRule.catch_all,
  # ])
  # Cloudflare::Tunnel.update_configuration(client, account_id, tunnel.id, config)
  # ```
  module Tunnel
    # The status of a tunnel.
    enum Status
      # The tunnel has never been run.
      Inactive
      # The tunnel is active and able to serve traffic, but is in an
      # unhealthy state.
      Degraded
      # The tunnel is active and able to serve traffic.
      Healthy
      # The tunnel can not serve traffic: it has no connections to the
      # Cloudflare edge.
      Down

      def to_json(json : JSON::Builder) : Nil
        json.string(to_s.underscore)
      end

      def self.new(pull : JSON::PullParser) : Status
        value = pull.read_string
        values.find { |member| member.to_s.underscore == value } ||
          raise JSON::ParseException.new(%(Unknown tunnel status: "#{value}"), 0, 0)
      end
    end

    # The type of a tunnel (`tun_type`).
    enum Type
      # A cloudflared tunnel.
      CfdTunnel
      WarpConnector
      Warp
      Magic
      IpSec
      Gre
      Cni

      def to_json(json : JSON::Builder) : Nil
        json.string(to_s.underscore)
      end

      def self.new(pull : JSON::PullParser) : Type
        value = pull.read_string
        values.find { |member| member.to_s.underscore == value } ||
          raise JSON::ParseException.new(%(Unknown tunnel type: "#{value}"), 0, 0)
      end
    end

    # Indicates whether a tunnel is configured locally or remotely
    # (`config_src`).
    enum ConfigSrc
      # The tunnel is configured through a YAML file on the origin machine.
      Local
      # The tunnel is configured remotely on the Zero Trust dashboard
      # (or through the `configurations` endpoints).
      Cloudflare

      def to_json(json : JSON::Builder) : Nil
        json.string(to_s.underscore)
      end

      def self.new(pull : JSON::PullParser) : ConfigSrc
        value = pull.read_string
        values.find { |member| member.to_s.underscore == value } ||
          raise JSON::ParseException.new(%(Unknown tunnel config source: "#{value}"), 0, 0)
      end
    end

    # A connection between a cloudflared instance and the Cloudflare edge.
    struct Connection
      include JSON::Serializable

      # UUID of the connection.
      getter id : String

      # Deprecated alias of `id`.
      getter uuid : String?

      # UUID of the cloudflared connector (replica) holding this connection.
      getter client_id : String?

      # The cloudflared version used to establish this connection.
      getter client_version : String?

      # The Cloudflare data center serving this connection (e.g. `"DFW"`).
      getter colo_name : String?

      # Deprecated by Cloudflare: always `false`.
      getter is_pending_reconnect : Bool?

      # The public IP address of the host running cloudflared.
      getter origin_ip : String?

      # Timestamp of when the connection was established.
      @[JSON::Field(converter: Cloudflare::NilableTimeConverter)]
      getter opened_at : Time?
    end

    # Cloudflare Access validation applied by cloudflared to requests for a
    # public hostname (`originRequest.access`).
    struct Access
      include JSON::Serializable

      # Audience tags of the Access applications allowed to reach the hostname.
      @[JSON::Field(key: "audTag", emit_null: false)]
      property aud_tag : Array(String)?

      @[JSON::Field(key: "teamName", emit_null: false)]
      property team_name : String?

      # Deny traffic that has not fulfilled Access authorization.
      @[JSON::Field(emit_null: false)]
      property required : Bool?

      def initialize(*, @aud_tag : Array(String)? = nil,
                     @team_name : String? = nil,
                     @required : Bool? = nil)
      end
    end

    # Connection settings between cloudflared and the origin server
    # (`originRequest`). Can be set globally on `Config` or per
    # `IngressRule`.
    struct OriginRequest
      include JSON::Serializable

      @[JSON::Field(emit_null: false)]
      property access : Access?

      # Path to the certificate authority (CA) for the certificate of your origin.
      @[JSON::Field(key: "caPool", emit_null: false)]
      property ca_pool : String?

      # Timeout (in seconds) for establishing a new TCP connection to your origin.
      @[JSON::Field(key: "connectTimeout", emit_null: false)]
      property connect_timeout : Int32?

      # Disables chunked transfer encoding (useful for WSGI servers).
      @[JSON::Field(key: "disableChunkedEncoding", emit_null: false)]
      property disable_chunked_encoding : Bool?

      # Attempt to connect to the origin using HTTP/2 (origin must be https).
      @[JSON::Field(key: "http2Origin", emit_null: false)]
      property http2_origin : Bool?

      # Sets the HTTP Host header on requests sent to the local service.
      @[JSON::Field(key: "httpHostHeader", emit_null: false)]
      property http_host_header : String?

      # Maximum number of idle keepalive connections to the origin.
      @[JSON::Field(key: "keepAliveConnections", emit_null: false)]
      property keep_alive_connections : Int32?

      # Timeout (in seconds) after which an idle keepalive connection is discarded.
      @[JSON::Field(key: "keepAliveTimeout", emit_null: false)]
      property keep_alive_timeout : Int32?

      # Auto-configure the hostname on the origin server certificate.
      @[JSON::Field(key: "matchSNItoHost", emit_null: false)]
      property match_sni_to_host : Bool?

      # Disable the "happy eyeballs" algorithm for IPv4/IPv6 fallback.
      @[JSON::Field(key: "noHappyEyeballs", emit_null: false)]
      property no_happy_eyeballs : Bool?

      # Disable TLS verification of the certificate presented by the origin.
      @[JSON::Field(key: "noTLSVerify", emit_null: false)]
      property no_tls_verify : Bool?

      # Hostname that cloudflared should expect from the origin certificate.
      @[JSON::Field(key: "originServerName", emit_null: false)]
      property origin_server_name : String?

      # Proxy type for TCP traffic: `""` (regular) or `"socks"` (SOCKS5).
      @[JSON::Field(key: "proxyType", emit_null: false)]
      property proxy_type : String?

      # Timeout (in seconds) after which a TCP keepalive packet is sent.
      @[JSON::Field(key: "tcpKeepAlive", emit_null: false)]
      property tcp_keep_alive : Int32?

      # Timeout (in seconds) for completing a TLS handshake to the origin.
      @[JSON::Field(key: "tlsTimeout", emit_null: false)]
      property tls_timeout : Int32?

      def initialize(*, @access : Access? = nil,
                     @ca_pool : String? = nil,
                     @connect_timeout : Int32? = nil,
                     @disable_chunked_encoding : Bool? = nil,
                     @http2_origin : Bool? = nil,
                     @http_host_header : String? = nil,
                     @keep_alive_connections : Int32? = nil,
                     @keep_alive_timeout : Int32? = nil,
                     @match_sni_to_host : Bool? = nil,
                     @no_happy_eyeballs : Bool? = nil,
                     @no_tls_verify : Bool? = nil,
                     @origin_server_name : String? = nil,
                     @proxy_type : String? = nil,
                     @tcp_keep_alive : Int32? = nil,
                     @tls_timeout : Int32? = nil)
      end
    end

    # A single ingress rule, mapping a public hostname (and optional path) to
    # a local service. The last rule of a configuration must be a catch-all
    # rule without hostname, see `IngressRule.catch_all`.
    struct IngressRule
      include JSON::Serializable

      # Public hostname for this service (absent on the catch-all rule).
      @[JSON::Field(emit_null: false)]
      property hostname : String?

      # Protocol and address of the destination server, e.g.
      # `"http://localhost:8080"`, `"tcp://localhost:22"` or a status code
      # shorthand such as `"http_status:404"`.
      property service : String

      # Only requests with this path route to this rule's service.
      @[JSON::Field(emit_null: false)]
      property path : String?

      # Origin connection settings specific to this rule.
      @[JSON::Field(key: "originRequest", emit_null: false)]
      property origin_request : OriginRequest?

      def initialize(@service : String, *,
                     @hostname : String? = nil,
                     @path : String? = nil,
                     @origin_request : OriginRequest? = nil)
      end

      # The catch-all rule required as the last ingress rule of every tunnel
      # configuration (responds with 404 by default).
      def self.catch_all(service : String = "http_status:404") : IngressRule
        new(service)
      end
    end

    # The `config` payload of a tunnel configuration: ingress rules plus
    # global origin connection settings.
    struct Config
      include JSON::Serializable

      # Ordered list of ingress rules. Must end with a catch-all rule.
      property ingress : Array(IngressRule)

      # Global origin connection settings.
      @[JSON::Field(key: "originRequest", emit_null: false)]
      property origin_request : OriginRequest?

      def initialize(@ingress : Array(IngressRule) = [] of IngressRule, *,
                     @origin_request : OriginRequest? = nil)
      end
    end

    # A tunnel configuration as returned by the `configurations` endpoints.
    struct Configuration
      include JSON::Serializable

      getter tunnel_id  : String
      getter account_id : String?

      # The version of the tunnel configuration.
      getter version : Int32

      getter source : ConfigSrc?
      getter config : Config

      @[JSON::Field(converter: Cloudflare::NilableTimeConverter)]
      getter created_at : Time?
    end

    # A Cloudflare Tunnel connecting an origin to Cloudflare's edge.
    struct Tunnel
      include JSON::Serializable

      # UUID of the tunnel.
      getter id : String

      # Cloudflare account ID owning the tunnel.
      getter account_tag : String

      # The user-friendly name of the tunnel.
      getter name : String

      @[JSON::Field(converter: Cloudflare::TimeConverter)]
      getter created_at : Time

      # Timestamp of when the tunnel was deleted (`nil` if not deleted).
      @[JSON::Field(converter: Cloudflare::NilableTimeConverter)]
      getter deleted_at : Time?

      # Timestamp of when the tunnel first established at least one
      # connection (`nil` if it never connected).
      @[JSON::Field(converter: Cloudflare::NilableTimeConverter)]
      getter conns_active_at : Time?

      # Timestamp of when the tunnel became inactive (`nil` if active).
      @[JSON::Field(converter: Cloudflare::NilableTimeConverter)]
      getter conns_inactive_at : Time?

      getter tun_type   : Type?
      getter status     : Status?
      getter config_src : ConfigSrc?

      # Metadata associated with the tunnel.
      getter metadata : Hash(String, JSON::Any) = {} of String => JSON::Any

      # Deprecated: Cloudflare will start returning an empty array here.
      # Use `Tunnel.connections` (the dedicated endpoint) instead.
      getter connections : Array(Connection) = [] of Connection

      # Deprecated by Cloudflare: use `config_src` instead.
      getter remote_config : Bool?

      # The tunnel token. Only present on create/update responses for
      # tunnels Cloudflare can show it for; use `Tunnel.token` otherwise.
      getter token : String?

      def deleted? : Bool
        !deleted_at.nil?
      end

      def healthy? : Bool
        status == Status::Healthy
      end

      # Whether the tunnel has ever connected to Cloudflare's edge.
      def active? : Bool
        !conns_active_at.nil?
      end
    end

    # :nodoc:
    private struct CreateRequest
      include JSON::Serializable

      getter name : String

      @[JSON::Field(emit_null: false)]
      getter config_src : ConfigSrc?

      @[JSON::Field(emit_null: false)]
      getter tunnel_secret : String?

      def initialize(@name : String,
                     @config_src : ConfigSrc? = nil,
                     @tunnel_secret : String? = nil)
      end
    end

    # :nodoc:
    private struct UpdateRequest
      include JSON::Serializable

      @[JSON::Field(emit_null: false)]
      getter name : String?

      @[JSON::Field(emit_null: false)]
      getter tunnel_secret : String?

      def initialize(@name : String? = nil, @tunnel_secret : String? = nil)
      end
    end

    # :nodoc:
    private struct ConfigurationRequest
      include JSON::Serializable

      getter config : Config

      def initialize(@config : Config)
      end
    end

    # Lists tunnels of an account.
    #
    # Maps `GET /accounts/:account_id/cfd_tunnel`.
    def self.list(client : Client, account_id : String, *,
                  name : String? = nil,
                  is_deleted : Bool? = nil,
                  uuid : String? = nil,
                  status : Status? = nil,
                  existed_at : Time? = nil,
                  was_active_at : Time? = nil,
                  was_inactive_at : Time? = nil,
                  include_prefix : String? = nil,
                  exclude_prefix : String? = nil,
                  page : Int32? = nil,
                  per_page : Int32? = nil) : Cloudflare::List(Tunnel)
      params = URI::Params.new
      params["name"] = name if name
      params["is_deleted"] = is_deleted.to_s unless is_deleted.nil?
      params["uuid"] = uuid if uuid
      params["status"] = status.to_s.underscore if status
      params["existed_at"] = existed_at.to_rfc3339 if existed_at
      params["was_active_at"] = was_active_at.to_rfc3339 if was_active_at
      params["was_inactive_at"] = was_inactive_at.to_rfc3339 if was_inactive_at
      params["include_prefix"] = include_prefix if include_prefix
      params["exclude_prefix"] = exclude_prefix if exclude_prefix
      params["page"] = page.to_s if page
      params["per_page"] = per_page.to_s if per_page

      envelope = client.get(tunnels_path(account_id), params: params)
      Cloudflare::List(Tunnel).new(extract(envelope, Array(Tunnel)), envelope.result_info)
    end

    # Gets a tunnel by ID.
    #
    # Maps `GET /accounts/:account_id/cfd_tunnel/:tunnel_id`.
    def self.get(client : Client, account_id : String, tunnel_id : String) : Tunnel
      extract(client.get(tunnel_path(account_id, tunnel_id)), Tunnel)
    end

    # Creates a tunnel named *name*.
    #
    # *config_src* selects where the tunnel is configured (`ConfigSrc::Local`
    # or `ConfigSrc::Cloudflare`, Cloudflare's default is `local`).
    # *tunnel_secret* sets the password required to run a locally-managed
    # tunnel (base64-encoded, at least 32 bytes — see `Tunnel.generate_secret`).
    #
    # Maps `POST /accounts/:account_id/cfd_tunnel`.
    def self.create(client : Client, account_id : String, name : String, *,
                    config_src : ConfigSrc? = nil,
                    tunnel_secret : String? = nil) : Tunnel
      body = CreateRequest.new(name, config_src, tunnel_secret)
      extract(client.post(tunnels_path(account_id), body: body.to_json), Tunnel)
    end

    # Updates the name and/or secret of a tunnel.
    #
    # Maps `PATCH /accounts/:account_id/cfd_tunnel/:tunnel_id`.
    def self.update(client : Client, account_id : String, tunnel_id : String, *,
                    name : String? = nil,
                    tunnel_secret : String? = nil) : Tunnel
      if name.nil? && tunnel_secret.nil?
        raise ArgumentError.new("Must provide at least one of `name` or `tunnel_secret`")
      end
      body = UpdateRequest.new(name, tunnel_secret)
      extract(client.patch(tunnel_path(account_id, tunnel_id), body: body.to_json), Tunnel)
    end

    # Deletes (archives) a tunnel.
    #
    # Maps `DELETE /accounts/:account_id/cfd_tunnel/:tunnel_id`.
    def self.delete(client : Client, account_id : String, tunnel_id : String) : Tunnel
      extract(client.delete(tunnel_path(account_id, tunnel_id)), Tunnel)
    end

    # Gets the token used to run (a replica of) a tunnel.
    #
    # Maps `GET /accounts/:account_id/cfd_tunnel/:tunnel_id/token`.
    def self.token(client : Client, account_id : String, tunnel_id : String) : String
      extract(client.get("#{tunnel_path(account_id, tunnel_id)}/token"), String)
    end

    # Gets the configuration of a remotely-managed tunnel.
    #
    # Maps `GET /accounts/:account_id/cfd_tunnel/:tunnel_id/configurations`.
    def self.get_configuration(client : Client, account_id : String, tunnel_id : String) : Configuration
      extract(client.get("#{tunnel_path(account_id, tunnel_id)}/configurations"), Configuration)
    end

    # Replaces the configuration of a remotely-managed tunnel.
    #
    # Maps `PUT /accounts/:account_id/cfd_tunnel/:tunnel_id/configurations`.
    def self.update_configuration(client : Client, account_id : String, tunnel_id : String,
                                  config : Config) : Configuration
      body = ConfigurationRequest.new(config)
      extract(client.put("#{tunnel_path(account_id, tunnel_id)}/configurations", body: body.to_json), Configuration)
    end

    # Lists the active connections of a tunnel.
    #
    # Maps `GET /accounts/:account_id/cfd_tunnel/:tunnel_id/connections`.
    def self.connections(client : Client, account_id : String, tunnel_id : String) : Cloudflare::List(Connection)
      envelope = client.get("#{tunnel_path(account_id, tunnel_id)}/connections")
      Cloudflare::List(Connection).new(extract(envelope, Array(Connection)), envelope.result_info)
    end

    # Cleans up inactive connections of a tunnel.
    #
    # Maps `DELETE /accounts/:account_id/cfd_tunnel/:tunnel_id/connections`.
    def self.clean_connections(client : Client, account_id : String, tunnel_id : String) : Nil
      client.delete("#{tunnel_path(account_id, tunnel_id)}/connections")
      nil
    end

    # Generates a base64-encoded 32-byte secret suitable for the
    # *tunnel_secret* argument of `create`/`update`.
    def self.generate_secret : String
      Base64.strict_encode(Random::Secure.random_bytes(32))
    end

    private def self.tunnels_path(account_id : String) : String
      "/accounts/#{account_id}/cfd_tunnel"
    end

    private def self.tunnel_path(account_id : String, tunnel_id : String) : String
      "#{tunnels_path(account_id)}/#{tunnel_id}"
    end

    # :nodoc:
    # Decodes the `result` payload of an envelope into *type*.
    private def self.extract(envelope : Cloudflare::Envelope, as type : T.class) : T forall T
      raw = envelope.result ||
            raise UnexpectedResponseError.new("Response did not contain a result")
      T.from_json(raw.to_json)
    end
  end
end
