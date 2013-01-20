require 'spec_helper.rb'
require 'resolv'
require 'chef/resolver_server'

describe Chef::ResolverServer do
  TESTING_DNS_PORT = 20571

  def start_server config
    @server = Chef::ResolverServer.new TESTING_DNS_PORT, config
    @server.run
  end

  def stop_server
    @server.stop if @server
    @server = nil
  end

  def stub_search role, nodes
    query = double('Chef::Search::Query')
    nodes.each_with_index {|n, i| n['name'] = "node #{i}" }
    query.should_receive(:search).with('node', "role:#{role}").and_return([nodes, 0, nodes.length])
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
    @default_config = Chef::Config.configuration
    @test_config = {'knife_file' => File.dirname(__FILE__)+'/knife/test_knife.rb'}
    @test2_config = {'knife_file' => File.dirname(__FILE__)+'/knife/test2_knife.rb', 'env' => {'ENV_PROP' => 'test2'}}
  end

  after :each do
    stop_server
    Chef::Config.configuration = @default_config.dup
  end

  it "should load chef config" do
    start_server 'test' => @test_config
    @server.load_chef_config @test_config
    Chef::Config.test_prop.should == true
  end

  it "should properly reset chef config between loads" do
    start_server 'test' => @test_config, 'test2' => @test2_config
    @server.load_chef_config @test_config
    Chef::Config.test_prop.should == true
    Chef::Config.shared_prop.should == 'test_knife'

    @server.load_chef_config @test2_config
    Chef::Config.test_prop.should be_nil
    Chef::Config.test2_prop.should == true
    Chef::Config.shared_prop.should == 'test2_knife'
  end

  it "should properly reset ENV between chef config loads" do
    start_server 'test' => @test_config, 'test2' => @test2_config
    @server.load_chef_config @test_config
    @server.load_chef_config @test2_config
    Chef::Config.env_prop.should == 'test2'

    @server.load_chef_config @test_config
    Chef::Config.env_prop.should be_nil
  end

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