require 'webrick'
require 'webrick/https'
require 'openssl'
require 'net/http'

# Set up SSL/HTTPS configuration
server = WEBrick::HTTPServer.new(
  Port: 443,
  SSLEnable: true,
  SSLVerifyClient: OpenSSL::SSL::VERIFY_NONE,
  SSLCertificate: OpenSSL::X509::Certificate.new(File.read("path/to/your/cert.pem")),
  SSLPrivateKey: OpenSSL::PKey::RSA.new(File.read("path/to/your/private_key.pem")),
  SSLCertName: [["CN", WEBrick::Utils.getservername]]
)

# Handle HTTP to HTTP backend
server.mount_proc '/' do |req, res|
  uri = URI.parse("http://your-backend-server.com#{req.path}")
  proxy_request = Net::HTTP::GenericRequest.new(req.request_method, req.body.nil?, true, uri.request_uri)
  
  http = Net::HTTP.new(uri.host, uri.port)
  backend_response = http.request(proxy_request)
  
  res.body = backend_response.body
  res.status = backend_response.code.to_i
  res.content_type = backend_response.content_type
end

trap 'INT' do
  server.shutdown
end

server.start
