require 'webrick'
require 'webrick/https'
require 'openssl'
require 'net/http'

# Set up SSL/HTTPS configuration
server = WEBrick::HTTPServer.new(
  Port: 443,
  SSLEnable: true,
  SSLVerifyClient: OpenSSL::SSL::VERIFY_NONE,
  SSLCertificate: OpenSSL::X509::Certificate.new(File.read("cert.pem")),
  SSLPrivateKey: OpenSSL::PKey::RSA.new(File.read("key.pem")),
  SSLCertName: [["AU", WEBrick::Utils.getservername]]
)

def map_request_class(method)
  case method
  when 'GET'
    Net::HTTP::Get
  when 'POST'
    Net::HTTP::Post
  when 'PUT'
    Net::HTTP::Put
  when 'DELETE'
    Net::HTTP::Delete
  when 'HEAD'
    Net::HTTP::Head
  else
    raise "Unsupported HTTP method: #{method}"
  end
end

# Handle HTTP to HTTP backend
server.mount_proc '/' do |req, res|
  uri = URI.parse("http://127.0.0.1:3000#{req.path}")

# Map request method to appropriate Net::HTTP class
  request_class = map_request_class(req.request_method)
  
  # Create a new request instance with the same method as the original request
  proxy_request = request_class.new(uri)
  
  # Pass headers from the original request to the proxy request
  req.header.each { |key, value| proxy_request[key] = value }

  # If the request has a body (e.g., POST), pass it along as well
  proxy_request.body = req.body if req.body

  # Send the request to the backend server
  http = Net::HTTP.new(uri.host, uri.port)
  backend_response = http.request(proxy_request)

  # Set response status, headers, and body based on the backend response
  res.status = backend_response.code.to_i
  res.body = backend_response.body
  backend_response.each_header { |key, value| res[key] = value }
end

trap 'INT' do
  server.shutdown
end

server.start
