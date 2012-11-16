Gem::Specification.new do |s|
  s.name        = 'sapoku'
  s.version     = '0.0.5'
  s.date        = '2012-11-16'
  s.summary     = "Manages Sapoku instances"
  s.description = "Manages Sapoku instances"
  s.authors     = ["Fred Oliveira"]
  s.email       = 'fred@helloform.com'
  s.files       = ["lib/sapoku.rb"]
  s.homepage    = 'http://rubygems.org/gems/hola'

  s.add_dependency('redis')
end