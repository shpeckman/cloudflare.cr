# src/cloudflare.cr
require "http/client"
require "json"
require "uri"
require "uri/params"

require "./cloudflare/errors"
require "./cloudflare/response"
require "./cloudflare/converters"
require "./cloudflare/list"
require "./cloudflare/client"
require "./cloudflare/tunnel"

# A Crystal client for the Cloudflare API v4.
#
# Currently implemented:
#
# * `Cloudflare::Tunnel` — Cloudflare Tunnel (cloudflared) management.
#
# ```
# require "cloudflare"
#
# client = Cloudflare::Client.from_env # reads CLOUDFLARE_API_TOKEN
# account_id = "699d98642c564d2e855e9661899b7252"
#
# tunnels = Cloudflare::Tunnel.list(client, account_id)
# tunnels.each do |tunnel|
#   puts "#{tunnel.id}: #{tunnel.name} (#{tunnel.status})"
# end
# ```
module Cloudflare
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
end
