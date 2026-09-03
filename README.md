# cloudflare.cr

A Crystal client for the [Cloudflare API v4](https://developers.cloudflare.com/api/).

Currently implemented:

* **`Cloudflare::Tunnel`** — Cloudflare Tunnel (cloudflared / Zero Trust tunnels): CRUD, tokens, configuration, and connections.

Requires **Crystal >= 1.21.0**.

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  cloudflare:
    github: shpeckman/cloudflare.cr
```

Then run `shards install`.

## Getting started

All requests go through `Cloudflare::Client`, which authenticates with an
[API token](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)
(`Authorization: Bearer ...`). Managing tunnels requires a token with the
*Cloudflare Tunnel: Edit* account permission.

```crystal
require "cloudflare"

# Reads the CLOUDFLARE_API_TOKEN environment variable:
client = Cloudflare::Client.from_env

# Or pass a token (and optionally a base URL / timeouts) explicitly:
client = Cloudflare::Client.new("your-api-token")

account_id = "699d98642c564d2e855e9661899b7252"
```

## Cloudflare Tunnel

Maps the `cfd_tunnel` endpoints of the API:
<https://developers.cloudflare.com/api/resources/zero_trust/subresources/tunnels/>

### List tunnels

```crystal
tunnels = Cloudflare::Tunnel.list(client, account_id)

tunnels.each do |tunnel|
  puts "#{tunnel.id} #{tunnel.name} #{tunnel.status}"
end

# With filters:
healthy = Cloudflare::Tunnel.list(client, account_id,
  status: Cloudflare::Tunnel::Status::Healthy,
  exclude_prefix: "staging-",
  per_page: 50)

# Pagination metadata is available on the result:
healthy.total_count # => Int32?
healthy.page        # => Int32?
```

### Create a tunnel

```crystal
# Remotely-managed tunnel (configured via dashboard / API):
tunnel = Cloudflare::Tunnel.create(client, account_id, "my-tunnel",
  config_src: Cloudflare::Tunnel::ConfigSrc::Cloudflare)

# Locally-managed tunnel (configured via a YAML file on the origin).
# The secret must be at least 32 bytes, base64-encoded:
secret = Cloudflare::Tunnel.generate_secret
tunnel = Cloudflare::Tunnel.create(client, account_id, "my-tunnel",
  config_src: Cloudflare::Tunnel::ConfigSrc::Local,
  tunnel_secret: secret)
```

The create/update response includes a `token` when Cloudflare can show one;
otherwise fetch it explicitly:

```crystal
token = Cloudflare::Tunnel.token(client, account_id, tunnel.id)
# cloudflared service install <token>
```

### Configure ingress (publish an application)

```crystal
config = Cloudflare::Tunnel::Config.new([
  Cloudflare::Tunnel::IngressRule.new("http://localhost:8080",
    hostname: "app.example.com",
    origin_request: Cloudflare::Tunnel::OriginRequest.new(no_tls_verify: true)),
  Cloudflare::Tunnel::IngressRule.catch_all, # required last rule
])

Cloudflare::Tunnel.update_configuration(client, account_id, tunnel.id, config)

current = Cloudflare::Tunnel.get_configuration(client, account_id, tunnel.id)
current.version # => 1
```

### Inspect and clean up connections

```crystal
connections = Cloudflare::Tunnel.connections(client, account_id, tunnel.id)
connections.each do |conn|
  puts "#{conn.colo_name} via #{conn.origin_ip} (#{conn.client_version})"
end

Cloudflare::Tunnel.clean_connections(client, account_id, tunnel.id)
```

### Update and delete

```crystal
Cloudflare::Tunnel.update(client, account_id, tunnel.id, name: "renamed-tunnel")
Cloudflare::Tunnel.delete(client, account_id, tunnel.id)
```

## Types

| Type | Purpose |
| ---- | ------- |
| `Cloudflare::Tunnel::Tunnel` | A tunnel resource (`id`, `name`, `status`, `tun_type`, timestamps, `healthy?`, `deleted?`, `active?`, ...) |
| `Cloudflare::Tunnel::Connection` | An edge connection held by a cloudflared replica |
| `Cloudflare::Tunnel::Configuration` | A versioned tunnel configuration (`config`, `version`, `source`) |
| `Cloudflare::Tunnel::Config` | The `config` payload: `ingress` rules + global `origin_request` |
| `Cloudflare::Tunnel::IngressRule` | One ingress rule (`hostname`, `service`, `path`, `origin_request`) |
| `Cloudflare::Tunnel::OriginRequest` / `Access` | Origin connection settings (API camelCase keys mapped to snake_case) |
| `Cloudflare::Tunnel::Status` | `Inactive`, `Degraded`, `Healthy`, `Down` |
| `Cloudflare::Tunnel::Type` | `CfdTunnel`, `WarpConnector`, `Warp`, `Magic`, `IpSec`, `Gre`, `Cni` |
| `Cloudflare::Tunnel::ConfigSrc` | `Local` or `Cloudflare` |
| `Cloudflare::List(T)` | A page of results plus `ResultInfo` pagination metadata |

Enums (de)serialize using the API's wire values (`"cfd_tunnel"`, `"healthy"`,
...) and raise `JSON::ParseException` on unknown values. Timestamps are parsed
as `Time` from RFC 3339 (with fractional seconds); absent timestamps are `nil`.

## Error handling

```crystal
begin
  Cloudflare::Tunnel.list(client, account_id)
rescue ex : Cloudflare::APIError
  # The API answered with success: false
  ex.status_code # => 403
  ex.errors.each { |e| puts "#{e.code}: #{e.message}" }
rescue ex : Cloudflare::UnexpectedResponseError
  # The response could not be decoded (e.g. a non-JSON proxy error page)
  ex.status_code # => 502
  ex.body
end
```

`Cloudflare::Error` is the common base class of every error raised by this shard.

## Endpoints not covered yet

`Cloudflare::Client#request` is public, so any v4 endpoint can be reached while
waiting for a typed module:

```crystal
envelope = client.get("/user/tokens/verify")
envelope.result # => JSON::Any?
```

## Development

```console
$ crystal spec   # run the test suite (uses a local stub server, no network needed)
$ crystal tool format --check src spec
```

## Contributing

1. Fork it (<https://github.com/your-user/cloudflare.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

MIT
