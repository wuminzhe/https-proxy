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

# Define backend routes
ROUTES = {
  '/gateway' => {
    backend_url: 'http://127.0.0.1:8080',
    strip_prefix: true
  },
  '/subnames' => {
    backend_url: 'http://127.0.0.1:4350/graphql',
    strip_prefix: true
  }
}

# Handle HTTP to HTTP backend
server.mount_proc '/' do |req, res|
  # Find matching route
  route = ROUTES.find { |prefix, _| req.path.start_with?(prefix) }
  
  if route
    prefix, config = route
    backend_url = config[:backend_url]
    
    # Remove the prefix if configured
    backend_path = if config[:strip_prefix]
      req.path.sub(prefix, '')
    else
      req.path
    end
    
    # Handle empty path after stripping
    backend_path = '/' if backend_path.empty?
    
    # Construct full backend URL
    backend_server_fullpath = "#{backend_url}#{backend_path}"
    puts "Proxying request to #{backend_server_fullpath}"

    # # test, just set the beckend_server_fullpath to user
    # res.body = backend_server_fullpath

    uri = URI.parse(backend_server_fullpath)
    request_class = map_request_class(req.request_method)
    proxy_request = request_class.new(uri)
    req.header.each { |key, value| proxy_request[key] = value }
    proxy_request.body = req.body if req.body
    
    http = Net::HTTP.new(uri.host, uri.port)
    backend_response = http.request(proxy_request)
    res.status = backend_response.code.to_i
    res.body = backend_response.body
    backend_response.each_header { |key, value| res[key] = value }
  else
    res.status = 404
    res.body = "Not Found"
  end
end

trap 'INT' do
  server.shutdown
end

server.start
