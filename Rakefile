require 'rubygems'
require 'rake/gempackagetask'

PLUGIN = "sequel_mailer"
NAME = "sequel_mailer"
VERSION = "0.0.2"
AUTHOR = "Brian Cooke"
EMAIL = "bcooke@roobasoft.com"
HOMEPAGE = "http://"
SUMMARY = "Merb plugin that provides a :sequel mailer based on ar_mailer"

spec = Gem::Specification.new do |s|
  s.name = NAME
  s.version = VERSION
  s.platform = Gem::Platform::RUBY
  s.has_rdoc = true
  s.extra_rdoc_files = ["README", "LICENSE", 'TODO']
  s.summary = SUMMARY
  s.description = s.summary
  s.author = AUTHOR
  s.email = EMAIL
  s.homepage = HOMEPAGE
  s.add_dependency('merb-more', '>= 0.9.1')
  s.add_dependency('sequel_model', '>= 0.5.0.2')
  s.add_dependency('merb_sequel', '>= 0.9.1')
  s.require_path = 'lib'
  s.autorequire = PLUGIN
  s.bindir       = "bin"
  s.executables  = %w( sequel_sendmail )
  s.files = %w(LICENSE README Rakefile TODO) + Dir.glob("{lib,bin,specs}/**/*")
end

Rake::GemPackageTask.new(spec) do |pkg|
  pkg.gem_spec = spec
end

task :install => [:package] do
  sh %{sudo gem install pkg/#{NAME}-#{VERSION}}
end

namespace :jruby do

  desc "Run :package and install the resulting .gem with jruby"
  task :install => :package do
    sh %{#{SUDO} jruby -S gem install pkg/#{NAME}-#{Merb::VERSION}.gem --no-rdoc --no-ri}
  end
  
end