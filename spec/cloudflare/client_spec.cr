# spec/cloudflare/client_spec.cr
require "../spec_helper"
require "http/server"

describe Cloudflare::Client do
  it "performs requests against the API and decodes the envelope" do
    authorization : String? = nil
    request_body  : String? = nil

    server = HTTP::Server.new do |context|
      authorization = context.request.headers["Authorization"]?
      context.response.content_type = "application/json"

      case {context.request.method, context.request.path}
      when {"GET", "/client/v4/accounts/acct/cfd_tunnel"}
        context.response.print %({
          "success": true,
          "errors": [],
          "messages": [],
          "result": [#{TUNNEL_JSON}],
          "result_info": {"page": 1, "per_page": 20, "count": 1, "total_count": 1}
        })
      when {"POST", "/client/v4/accounts/acct/cfd_tunnel"}
        request_body = context.request.body.try &.gets_to_end
        context.response.print %({
          "success": true,
          "errors": [],
          "messages": [],
          "result": #{TUNNEL_JSON}
        })
      when {"GET", "/client/v4/accounts/acct/cfd_tunnel/f70ff985-a4ef-4643-bbbc-4a0ed4fc8415/token"}
        context.response.print %({
          "success": true,
          "errors": [],
          "messages": [],
          "result": "eyJhIjoiNWFiNGU5Z..."
        })
      else
        context.response.status_code = 404
        context.response.print %({
          "success": false,
          "errors": [{"code": 1000, "message": "not found"}],
          "messages": [],
          "result": null
        })
      end
    end

    address = server.bind_tcp("127.0.0.1", 0)
    spawn server.listen

    client = Cloudflare::Client.new("test-token",
      base_url: URI.parse("http://127.0.0.1:#{address.port}"))

    tunnels = Cloudflare::Tunnel.list(client, "acct")
    tunnels.size.should eq 1
    tunnels.total_count.should eq 1
    tunnels.first.name.should eq "Example tunnel"
    authorization.should eq "Bearer test-token"

    tunnel = Cloudflare::Tunnel.create(client, "acct", "Example tunnel",
      config_src: Cloudflare::Tunnel::ConfigSrc::Cloudflare)
    tunnel.id.should eq "f70ff985-a4ef-4643-bbbc-4a0ed4fc8415"
    request_body.should eq %({"name":"Example tunnel","config_src":"cloudflare"})

    token = Cloudflare::Tunnel.token(client, "acct", tunnel.id)
    token.should eq "eyJhIjoiNWFiNGU5Z..."

    server.close
  end

  it "raises APIError on error envelopes" do
    server = HTTP::Server.new do |context|
      context.response.status_code = 403
      context.response.print %({
        "success": false,
        "errors": [{"code": 9109, "message": "Invalid access token"}],
        "messages": [],
        "result": null
      })
    end

    address = server.bind_tcp("127.0.0.1", 0)
    spawn server.listen

    client = Cloudflare::Client.new("bad-token",
      base_url: URI.parse("http://127.0.0.1:#{address.port}"))

    error = expect_raises(Cloudflare::APIError) do
      Cloudflare::Tunnel.list(client, "acct")
    end
    error.status_code.should eq 403
    error.errors.first.code.should eq 9109
    error.message.should eq %(Cloudflare API request failed (HTTP 403): 9109 Invalid access token)

    server.close
  end

  it "raises UnexpectedResponseError on non-JSON responses" do
    server = HTTP::Server.new do |context|
      context.response.status_code = 502
      context.response.print "<html>bad gateway</html>"
    end

    address = server.bind_tcp("127.0.0.1", 0)
    spawn server.listen

    client = Cloudflare::Client.new("token",
      base_url: URI.parse("http://127.0.0.1:#{address.port}"))

    expect_raises(Cloudflare::UnexpectedResponseError) do
      Cloudflare::Tunnel.list(client, "acct")
    end

    server.close
  end

  it "builds clients from the environment" do
    ENV["CLOUDFLARE_SPEC_TOKEN"] = "env-token"
    Cloudflare::Client.from_env("CLOUDFLARE_SPEC_TOKEN").api_token.should eq "env-token"
  ensure
    ENV.delete("CLOUDFLARE_SPEC_TOKEN")
  end
end
