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

# Update the CORS headers method to handle specific origins
def add_cors_headers(response, request)
  # Get the origin from the request headers
  origin = request.header['origin']&.first || '*'
  
  response['Access-Control-Allow-Origin'] = origin
  response['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS, HEAD'
  response['Access-Control-Allow-Headers'] = 'Content-Type, Authorization, X-Requested-With'
  response['Access-Control-Allow-Credentials'] = 'true'
  response['Access-Control-Max-Age'] = '3600'
  
  # Add Vary header when dealing with CORS
  response['Vary'] = 'Origin'
  
  puts "Added CORS headers:"
  puts "Origin: #{origin}"
  puts "Request headers: #{request.header.inspect}"
  puts "Response headers: #{response.inspect}"
end

# Define backend routes
ROUTES = {
  '/0x' => {
    backend_url: 'http://127.0.0.1:8080',
    strip_prefix: false
  },
  '/subnames' => {
    backend_url: 'http://127.0.0.1:4350/graphql',
    strip_prefix: true
  },
  '/console' => {
    backend_url: 'http://127.0.0.1:4350/console',
    strip_prefix: true
  },
  '/graphql' => {
    backend_url: 'http://127.0.0.1:4350',
    strip_prefix: false
  }
}

# Add debugging in the request handler
server.mount_proc '/' do |req, res|
  puts "\nIncoming request:"
  puts "Method: #{req.request_method}"
  puts "Path: #{req.path}"
  puts "Headers: #{req.header.inspect}"
  
  # Handle OPTIONS preflight request first
  if req.request_method == 'OPTIONS'
    puts "Handling OPTIONS preflight request"
    add_cors_headers(res, req)
    res.status = 204  # No Content
    res['Content-Length'] = '0'
    return
  end
  
  # Add CORS headers for all other requests
  add_cors_headers(res, req)
  
  # Find matching route - update to handle exact matches
  route = ROUTES.find do |prefix, _| 
    if prefix == '/graphql'
      req.path == prefix  # Exact match for /graphql
    else
      req.path.start_with?(prefix)  # Prefix match for others
    end
  end
  
  if route
    prefix, config = route
    backend_url = config[:backend_url]
    
    # Construct the backend path
    backend_path = if config[:strip_prefix]
      req.path.sub(prefix, '')
    else
      req.path
    end
    
    puts "Route matched: #{prefix}"
    puts "Backend path: #{backend_path}"
    
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
    
    # Forward original headers except host
    req.header.each do |key, value| 
      next if key.downcase == 'host'
      proxy_request[key] = value 
    end
    
    proxy_request.body = req.body if req.body
    
    http = Net::HTTP.new(uri.host, uri.port)
    backend_response = http.request(proxy_request)
    res.status = backend_response.code.to_i
    res.body = backend_response.body
    
    # Forward backend response headers
    backend_response.each_header do |key, value|
      # Skip CORS headers from backend to use proxy's CORS headers
      next if key.downcase.start_with?('access-control-')
      res[key] = value
    end
  else
    res.status = 404
    res.body = "Not Found"
  end
end

trap 'INT' do
  server.shutdown
end

server.start
