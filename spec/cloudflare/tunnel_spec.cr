# spec/cloudflare/tunnel_spec.cr
require "../spec_helper"

# Realistic tunnel payload as returned by the API (shape documented in
# https://developers.cloudflare.com/api/resources/zero_trust/subresources/tunnels/).
TUNNEL_JSON = %({
  "id": "f70ff985-a4ef-4643-bbbc-4a0ed4fc8415",
  "account_tag": "699d98642c564d2e855e9661899b7252",
  "created_at": "2024-12-04T22:03:26.291225Z",
  "deleted_at": null,
  "name": "Example tunnel",
  "connections": [],
  "conns_active_at": null,
  "conns_inactive_at": "2024-12-04T22:03:26.291225Z",
  "tun_type": "cfd_tunnel",
  "metadata": {},
  "status": "inactive",
  "remote_config": true,
  "config_src": "cloudflare",
  "token": "eyJhIjoiNWFiNGU5Z..."
})

describe Cloudflare::Tunnel do
  describe "enums" do
    it "serializes to the wire format" do
      Cloudflare::Tunnel::Status::Healthy.to_json.should eq %("healthy")
      Cloudflare::Tunnel::Type::CfdTunnel.to_json.should eq %("cfd_tunnel")
      Cloudflare::Tunnel::Type::WarpConnector.to_json.should eq %("warp_connector")
      Cloudflare::Tunnel::ConfigSrc::Cloudflare.to_json.should eq %("cloudflare")
    end

    it "deserializes from the wire format" do
      Cloudflare::Tunnel::Status.from_json(%("down")).should eq Cloudflare::Tunnel::Status::Down
      Cloudflare::Tunnel::Type.from_json(%("ip_sec")).should eq Cloudflare::Tunnel::Type::IpSec
      Cloudflare::Tunnel::ConfigSrc.from_json(%("local")).should eq Cloudflare::Tunnel::ConfigSrc::Local
    end

    it "raises on unknown values" do
      expect_raises(JSON::ParseException) do
        Cloudflare::Tunnel::Status.from_json(%("bogus"))
      end
    end
  end

  describe Cloudflare::Tunnel::Tunnel do
    tunnel = Cloudflare::Tunnel::Tunnel.from_json(TUNNEL_JSON)

    it "parses a tunnel payload" do
      tunnel.id.should eq "f70ff985-a4ef-4643-bbbc-4a0ed4fc8415"
      tunnel.account_tag.should eq "699d98642c564d2e855e9661899b7252"
      tunnel.name.should eq "Example tunnel"
      tunnel.status.should eq Cloudflare::Tunnel::Status::Inactive
      tunnel.tun_type.should eq Cloudflare::Tunnel::Type::CfdTunnel
      tunnel.config_src.should eq Cloudflare::Tunnel::ConfigSrc::Cloudflare
      tunnel.token.should eq "eyJhIjoiNWFiNGU5Z..."
    end

    it "parses RFC 3339 timestamps with fractional seconds" do
      tunnel.created_at.year.should eq 2024
      tunnel.conns_inactive_at.should eq tunnel.created_at
    end

    it "exposes convenience predicates" do
      tunnel.deleted?.should be_false
      tunnel.healthy?.should be_false
      tunnel.active?.should be_false
    end

    it "round-trips through JSON" do
      reparsed = Cloudflare::Tunnel::Tunnel.from_json(tunnel.to_json)
      reparsed.id.should eq tunnel.id
      reparsed.status.should eq tunnel.status
    end
  end

  describe Cloudflare::Tunnel::IngressRule do
    it "builds a catch-all rule" do
      rule = Cloudflare::Tunnel::IngressRule.catch_all
      rule.service.should eq "http_status:404"
      rule.hostname.should be_nil
      rule.to_json.should eq %({"service":"http_status:404"})
    end
  end

  describe Cloudflare::Tunnel::Config do
    it "serializes with the API's camelCase keys" do
      config = Cloudflare::Tunnel::Config.new([
        Cloudflare::Tunnel::IngressRule.new("http://localhost:80",
          hostname: "app.example.com",
          origin_request: Cloudflare::Tunnel::OriginRequest.new(no_tls_verify: true)),
        Cloudflare::Tunnel::IngressRule.catch_all,
      ])
      json = config.to_json
      json.should contain %("hostname":"app.example.com")
      json.should contain %("originRequest":{"noTLSVerify":true})
      json.should contain %("http_status:404")
    end

    it "parses a configuration payload" do
      configuration = Cloudflare::Tunnel::Configuration.from_json(%({
        "tunnel_id": "f70ff985-a4ef-4643-bbbc-4a0ed4fc8415",
        "account_id": "699d98642c564d2e855e9661899b7252",
        "version": 2,
        "source": "cloudflare",
        "created_at": "2024-12-04T22:03:26.291225Z",
        "config": {
          "ingress": [
            {"hostname": "app.example.com", "service": "http://localhost:80", "originRequest": {}},
            {"service": "http_status:404"}
          ]
        }
      }))
      configuration.version.should eq 2
      configuration.source.should eq Cloudflare::Tunnel::ConfigSrc::Cloudflare
      configuration.config.ingress.size.should eq 2
      configuration.config.ingress.first.hostname.should eq "app.example.com"
      configuration.config.ingress.last.hostname.should be_nil
    end
  end

  describe ".generate_secret" do
    it "generates 32 random bytes, base64-encoded" do
      secret = Cloudflare::Tunnel.generate_secret
      Base64.decode_string(secret).bytesize.should eq 32
      secret.should_not eq Cloudflare::Tunnel.generate_secret
    end
  end
end

# Forces the compiler to type-check every public API method (Crystal only
# checks methods that are actually instantiated). The proc is never called,
# so no HTTP request is ever performed.
module Cloudflare::Tunnel::CompileCheck
  def self.all(client : Cloudflare::Client)
    account_id = "account_id"
    tunnel_id  = "tunnel_id"

    Cloudflare::Tunnel.list(client, account_id)
    Cloudflare::Tunnel.list(client, account_id,
      name: "blog", is_deleted: false, uuid: tunnel_id,
      status: Cloudflare::Tunnel::Status::Healthy,
      existed_at: Time.utc, was_active_at: Time.utc, was_inactive_at: Time.utc,
      include_prefix: "vpc1-", exclude_prefix: "vpc0-",
      page: 1, per_page: 20)
    Cloudflare::Tunnel.get(client, account_id, tunnel_id)
    Cloudflare::Tunnel.create(client, account_id, "blog")
    Cloudflare::Tunnel.create(client, account_id, "blog",
      config_src: Cloudflare::Tunnel::ConfigSrc::Cloudflare,
      tunnel_secret: Cloudflare::Tunnel.generate_secret)
    Cloudflare::Tunnel.update(client, account_id, tunnel_id,
      name: "blog-2", tunnel_secret: "secret")
    Cloudflare::Tunnel.delete(client, account_id, tunnel_id)
    Cloudflare::Tunnel.token(client, account_id, tunnel_id)
    Cloudflare::Tunnel.get_configuration(client, account_id, tunnel_id)
    Cloudflare::Tunnel.update_configuration(client, account_id, tunnel_id,
      Cloudflare::Tunnel::Config.new([Cloudflare::Tunnel::IngressRule.catch_all]))
    Cloudflare::Tunnel.connections(client, account_id, tunnel_id)
    Cloudflare::Tunnel.clean_connections(client, account_id, tunnel_id)

    client.get("/accounts/#{account_id}/cfd_tunnel")
    client.post("/x", body: %({}))
    client.put("/x", body: %({}))
    client.patch("/x", body: %({}))
    client.delete("/x")
    client.request("GET", "/x", params: URI::Params.new)
  end
end

_typecheck = ->Cloudflare::Tunnel::CompileCheck.all(Cloudflare::Client)
