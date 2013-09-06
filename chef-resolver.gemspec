# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'chef/resolver/version'

Gem::Specification.new do |gem|
  gem.name          = "chef-resolver"
  gem.version       = Chef::Resolver::VERSION
  gem.authors       = ["Stephen Augenstein"]
  gem.email         = ["perl.programmer@gmail.com"]
  gem.description   = %q{A DNS resolver for Mac OS X that does role queries to resolve hostnames}
  gem.summary       = %q{Instead of doing knife search node role every time you want to look up a server, simply ssh into ROLE_NAME-##.chef}
  gem.homepage      = "https://github.com/warhammerkid/chef-resolver"

  gem.add_dependency('chef', '~> 11.6')

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]
end
