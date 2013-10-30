#!/usr/bin/env ruby

# Based off https://gist.github.com/torsten/74107

require 'socket'
require 'uri'
require 'base64'

class Proxy

  def run(proxy_port, server_address, server_port, user_header)
    @server_address, @server_port, @user_header = server_address, server_port, user_header
    begin
      # Start our server to handle connections (will raise things on errors)
      @socket = TCPServer.new(proxy_port)

      # Handle every request in another thread
      loop do
        s = @socket.accept
        Thread.new(s, &method(:handle_request))
      end

    # CTRL-C
    rescue Interrupt
      puts 'Got Interrupt..'
    # Ensure that we release the socket on errors
    ensure
      if @socket
        @socket.close
        puts 'Socked closed..'
      end
      puts 'Quitting.'
    end
  end

  def handle_request(to_client)
    request_line = to_client.readline

    verb    = request_line[/^\w+/]
    url     = request_line[/^\w+\s+(\S+)/, 1]
    version = request_line[/HTTP\/(1\.\d)\s*$/, 1]
    uri     = URI::parse(url)

    # Show what got requested
    puts((" %4s "%verb) + url)

    prelude = []
    prelude << "#{verb} #{uri.path}?#{uri.query} HTTP/#{version}\r\n"

    content_len = 0

    authenticated = false

    loop do
      line = to_client.readline

      if line =~ /^Content-Length:\s+(\d+)\s*$/
        content_len = $1.to_i
      end

      if line =~ /^Authorization: Basic (.+)$/
        username, password = *Base64.decode64($1).split(/:/)
        if password == "password"
          prelude << "#{@user_header}: #{username}\r\n"
          authenticated = true
        end
      elsif line.strip.empty?
        prelude << "Connection: close\r\n\r\n"
        break
      else
        prelude << line
      end
    end

    if authenticated
      to_server = TCPSocket.new(@server_address, @server_port)

      puts prelude.join("")
      to_server.write(prelude.join(""))

      if content_len >= 0
        to_server.write(to_client.read(content_len))
      end

      buff = ""
      loop do
        to_server.read(4048, buff)
        to_client.write(buff)
        break if buff.size < 4048
      end
    else
      to_client.write(
        "HTTP/#{version} 401 Not authorized\r\n" +
          "WWW-Authenticate: Basic realm=\"BLUECOAT\"\r\n" +
          "Connection: close\r\n" +
          "Content-Length: 0\r\n"
      )
    end

  rescue Exception => e
    puts e.message
    puts e.backtrace.join("\n")
  ensure
    # Close the sockets
    to_client.close
    to_server.close if to_server
  end

end


# Get parameters and start the server
if ARGV.size == 4
  proxy_port = ARGV[0].to_i
  server_address = ARGV[1].to_i
  server_port = ARGV[2].to_i
  user_header = ARGV[3]
else
  puts 'Usage: proxy.rb proxy_port server_address server_port user_header'
  exit 1
end

Proxy.new.run(proxy_port, server_address, server_port, user_header)
