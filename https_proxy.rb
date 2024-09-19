require 'webrick'
require 'webrick/https'
require 'net/http'
require 'uri'

# Configure the backend HTTP server to forward requests to
BACKEND_SERVER = 'http://127.0.0.1:3000' # Replace with your backend URL

# Create an HTTPS server with self-signed certificates
server = WEBrick::HTTPServer.new(
  Port: 443,
  SSLEnable: true,
  SSLCertificate: OpenSSL::X509::Certificate.new(File.read('cert.pem')),
  SSLPrivateKey: OpenSSL::PKey::RSA.new(File.read('key.pem')),
  SSLOptions: OpenSSL::SSL::OP_ALL,
  Logger: WEBrick::Log.new($stdout, WEBrick::Log::DEBUG),
  AccessLog: [[ $stdout, WEBrick::AccessLog::COMBINED_LOG_FORMAT ]]
)

# Proxy logic
server.mount_proc '/' do |req, res|
  # Prepare the backend request
  uri = URI.join(BACKEND_SERVER, req.path)
  http = Net::HTTP.new(uri.host, uri.port)

  # Create the backend request
  backend_req = Net::HTTP::GenericRequest.new(req.request_method, req.body.nil?, true, req.http_version)
  backend_req.initialize_http_header(req.header)
  backend_req.body = req.body

  # Send the request to the backend server
  backend_res = http.request(backend_req)

  # Copy the response from the backend to the client
  res.status = backend_res.code.to_i
  res.body = backend_res.body
  backend_res.each_header do |key, value|
    res[key] = value
  end
end

# Handle shutdown signal
trap 'INT' do
  server.shutdown
end

# Start the proxy server
server.start
