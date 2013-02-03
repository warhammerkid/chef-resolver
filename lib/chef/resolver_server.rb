require 'resolv'
require 'socket'
require 'chef'

class Chef
  class ResolverServer
    IPv4 = "127.0.0.1".freeze

    def initialize port, config
      @port = port
      if config.is_a?(String)
        load_config_from_file config
      else
        load_config config
      end
    end

    def start
      @server = UDPSocket.open
      @server.bind IPv4, @port
      @thread = Thread.new { process_requests }
    end

    def stop
      @thread.kill if @thread
      @listener.stop if @listener
    end

    def load_chef_config config
      @default_config ||= Chef::Config.configuration
      @original_env ||= ENV.to_hash
      @cached_configs ||= {}

      cache_key = config.object_id
      cached_config = @cached_configs[cache_key]
      if cached_config
        Chef::Config.configuration = cached_config
      else
        Chef::Config.configuration = @default_config.dup
        (config['env'] || []).each do |key, val|
          ENV[key] = val
        end
        Chef::Config.from_file(config['knife_file'])
        @cached_configs[cache_key] = Chef::Config.configuration
        ENV.replace(@original_env)
      end

      nil
    end

  private
    def load_config config
      domains = config.keys
      @root_domains = {}
      domains.each {|d| @root_domains[Resolv::DNS::Name.create("#{d}.chef.")] = config[d]}
      @root_domains[Resolv::DNS::Name.create("chef.")] = config[domains[0]] if domains.length == 1
    end

    def load_config_from_file config_path, listen = false
      raise "Could not find config file: #{config_path}" unless File.exist?(config_path)
      load_config YAML.load_file(config_path)
    end

    def resolve_host host
      puts "Resolving: #{host}"
      @root_domains.each do |domain, config|
        next unless host.subdomain_of?(domain)
        role_part = host.to_s.split('.')[0]
        if role_part =~ /^(.+)-(\d+)$/
          return query_chef $1, $2.to_i - 1, config
        else
          return query_chef role_part, 0, config
        end
      end
      return nil
    end

    def query_chef role, index, config
      load_chef_config config

      puts "\tLooking up role #{role}..."
      nodes = Chef::Search::Query.new.search('node', "role:#{role}")[0]
      if index >= nodes.length
        puts "\tIndex beyond bounds: #{index} vs #{nodes.length}"
        return nil
      else
        node = nodes[index]
        puts "\tFound node: #{node['name']}"
        return node.has_key?('ec2') ? node['ec2']['public_ipv4'] : node['ipaddress']
      end
    end

    def process_requests
      loop do
        data, from = @server.recvfrom(1024)
        msg = Resolv::DNS::Message.decode(data)

        a = Resolv::DNS::Message.new msg.id
        a.qr = 1
        a.opcode = msg.opcode
        a.aa = 1
        a.rd = msg.rd

        msg.each_question do |q, cls|
          next unless Resolv::DNS::Resource::IN::A == cls
          ip = resolve_host q
          if ip
            a.add_answer "#{q.to_s}.", 60, cls.new(ip)
          end
        end
        a.rcode = 3 unless a.answer.length > 0 # Not found

        @server.send a.encode, 0, from[2], from[1]
      end
    ensure
      @server.close
    end
  end
end