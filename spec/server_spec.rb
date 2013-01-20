require 'spec_helper.rb'
require 'resolv'
require 'knife-dns-resolver/server'

describe KnifeDNS::Server do
  TESTING_DNS_PORT = 20571

  def start_server config
    @server = KnifeDNS::Server.new TESTING_DNS_PORT, config
    @server.run
  end

  def stop_server
    @server.stop if @server
    @server = nil
  end

  def stub_search role, nodes
    query = double('Chef::Search::Query')
    query.should_receive(:search).with('node', "role:#{role}").and_return(nodes)
    Chef::Search::Query.should_receive(:new) { query }
  end

  def getaddress host
    unless @resolver
      klass = Class.new(Resolv::DNS::Config) do
        def nameserver_port
          lazy_initialize
          @nameserver_port ||= [['127.0.0.1', TESTING_DNS_PORT]]
          @nameserver_port
        end
      end
      config = klass.new(:nameserver => ['127.0.0.1'])
      @resolver = Resolv::DNS.new
      @resolver.instance_variable_set('@config', config)
    end
    return @resolver.getaddress(host).to_s
  end

  before :all do
    @test_config = {'knife_file' => File.dirname(__FILE__)+'/knife/test_knife.rb', 'env' => {'SHARED_PROP' => 'test'}}
    @test2_config = {'knife_file' => File.dirname(__FILE__)+'/knife/test2_knife.rb', 'env' => {'SHARED_PROP' => 'test2', 'UNSHARED_PROP' => 'unshared'}}
  end

  after :each do
    stop_server
  end

  it "should load chef config"
  it "should properly reset chef config between loads"
  it "should properly reset ENV between chef config loads"

  it "should resolve a name like ROLE.CONFIG.chef" do
    start_server 'test' => @test_config, 'test2' => @test2_config
    stub_search 'test_role', [{'ipaddress' => '1.1.1.1'}]
    getaddress('test_role.test2.chef').should == '1.1.1.1'
  end

  it "should resolve a name like ROLE-INDEX.CONFIG.chef" do
    start_server 'test' => @test_config
    stub_search 'test_role', [{'ipaddress' => '1.1.1.1'}, {'ipaddress' => '2.2.2.2'}, {'ipaddress' => '3.3.3.3'}, {'ipaddress' => '4.4.4.4'}]
    getaddress('test_role-3.test.chef').should == '3.3.3.3'
  end

  it "should resolve a name like ROLE.chef if only one config" do
    # Should fail with multiple configs
    start_server 'test' => @test_config, 'test2' => @test2_config
    expect { getaddress('test_role.chef') }.to raise_error(Resolv::ResolvError)
    stop_server

    # Should succeed with one config
    start_server 'test' => @test_config
    stub_search 'test_role', [{'ipaddress' => '1.1.1.1'}]
    getaddress('test_role.chef').should == '1.1.1.1'
  end

  it "should resolve ec2 node public ip addresses properly" do
    start_server 'test' => @test_config
    stub_search 'test_role', [{'ec2' => {'public_ipv4' => '1.1.1.1'}, 'ipaddress' => '0.0.0.0'}]
    getaddress('test_role.chef').should == '1.1.1.1'
  end
end