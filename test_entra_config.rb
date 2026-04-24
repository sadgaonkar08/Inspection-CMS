#!/usr/bin/env ruby
# Quick diagnostic script for Entra ID configuration

require 'uri'
require 'net/http'
require 'json'

puts "=== Entra ID Configuration Diagnostic ==="
puts ""

# Check environment variables
puts "1. Environment Variables:"
%w[AZURE_TENANT_ID AZURE_CLIENT_ID AZURE_CLIENT_SECRET].each do |var|
  value = ENV[var]
  if value && !value.empty?
    puts "   ✓ #{var} = #{value[0..7]}...#{value[-4..]}"
  else
    puts "   ✗ #{var} = NOT SET"
  end
end

puts ""
puts "2. Expected Redirect URI:"
puts "   https://geometriceng-icms-app.azurewebsites.net/users/auth/microsoft_graph/callback"

puts ""
puts "3. OAuth Authorization URL:"
tenant_id = ENV['AZURE_TENANT_ID']
client_id = ENV['AZURE_CLIENT_ID']
if tenant_id && client_id
  redirect_uri = "https://geometriceng-icms-app.azurewebsites.net/users/auth/microsoft_graph/callback"
  auth_url = "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/authorize?client_id=#{client_id}&redirect_uri=#{URI.encode_www_form_component(redirect_uri)}&response_type=code&scope=openid+profile+email+User.Read"
  puts "   #{auth_url[0..100]}..."
else
  puts "   ✗ Cannot generate URL - missing tenant/client ID"
end

puts ""
puts "=== Next Steps ==="
puts "1. Verify the redirect URI in Azure Portal matches exactly"
puts "2. Try logging in again and check Rails logs for errors"
puts "3. Ensure admin consent is granted for API permissions"