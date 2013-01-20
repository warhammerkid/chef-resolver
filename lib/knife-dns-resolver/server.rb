require 'resolv'
require 'socket'
require 'chef'

module KnifeDNS
  class Server
    def initialize(port, config)
      @server = UDPSocket.open
      @server.bind "127.0.0.1", port

      domains = config.keys
      @root_domains = {}
      domains.each {|d| @root_domains[Resolv::DNS::Name.create("#{d}.chef.")] = config[d]}
      @root_domains[Resolv::DNS::Name.create("chef.")] = config[domains[0]] if domains.length == 1
    end

    def resolve_host host
      puts "Resolving: #{host}"
      @root_domains.each do |domain, config|
        next unless host.subdomain_of?(domain)
        role_part = host.to_s.split('.')[0]
        if role_part =~ /^(.+)-(\d+)$/
          return query_knife $1, $2.to_i - 1, config
        else
          return query_knife role_part, 0, config
        end
      end
      return nil
    end

    def query_knife role, index, config
      load_chef_config config

      puts "\tLooking up role #{role}..."
      nodes = Chef::Search::Query.new.search('node', "role:#{role}")[0]
      if index >= nodes.length
        puts "\tIndex beyond bounds: #{index} vs #{nodes.length}"
        return nil
      else
        node = nodes[index]
        puts "\tFound node: #{node.name}"
        return node.has_key?('ec2') ? node['ec2']['public_ipv4'] : node['ipaddress']
      end
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

    def read_msg
      data, from = @server.recvfrom(1024)
      return Resolv::DNS::Message.decode(data), from
    end

    def answer(msg)
      a = Resolv::DNS::Message.new msg.id
      a.qr = 1
      a.opcode = msg.opcode
      a.aa = 1
      a.rd = msg.rd
      a.ra = 0
      a.rcode = 0
      a
    end

    def send_to(data, to)
      @server.send data, 0, to[2], to[1]
    end

    def run
      @thread = Thread.new do
        while true
          msg, from = read_msg

          a = answer(msg)

          msg.each_question do |q,cls|
            next unless Resolv::DNS::Resource::IN::A == cls
            ip = resolve_host q
            a.add_answer "#{q.to_s}.", 60, cls.new(ip) if ip
          end

          send_to a.encode, from
        end
      end
    end

    def stop
      @server.close
      @thread.kill if @thread
    end
  end
end