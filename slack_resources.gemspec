lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

HAS_VERSION = File.exist?('./lib/slack_resources/version.rb')
require 'slack_resources/version' if HAS_VERSION

Gem::Specification.new do |spec|
  spec.name          = 'slack_resources'
  spec.version       = HAS_VERSION ? SlackResources::VERSION : '0.0.0'
  spec.authors       = ['mmmpa']
  spec.email         = ['mmmpa.mmmpa@gmail.com']

  spec.summary       = 'slack resources'
  spec.description   = 'make you use slack resources'
  spec.homepage      = 'https://github.com/mmmpa/slack_resources'
  spec.license       = 'MIT'

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_development_dependency 'activesupport', '~> 5.2'
  spec.add_development_dependency 'bundler', '~> 1.16'
  spec.add_development_dependency 'dotenv', '~> 2.5'
  spec.add_development_dependency 'nokogiri', '~> 1.8'
  spec.add_development_dependency 'onkcop', '~> 0.53'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rest-client', '~> 2.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
end
