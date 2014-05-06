# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name        = 'data_tables'
  s.version     = '0.1.20'
  s.date        = Time.now.strftime("%Y-%m-%d")
  s.summary     = "Rails friendly interface into DataTables"
  s.description = "DataTables for Rails"
  s.authors     = ["Duane Compton", "Calvin Bascom", "Yi Su", "Chris Moos", "Adrian Mejia"]
  s.email       = 'Duane.Compton@gmail.com'
  s.homepage    = 'http://rubygems.org/gems/data_tables'
  s.platform    = Gem::Platform::RUBY

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.require_paths = ["lib"]

  s.add_development_dependency 'rspec', '~> 2.10'
end

