Gem::Specification.new do |s|
  s.name        = 'mondupe'
  s.version     = '0.0.29'
  s.date        = '2014-07-28'
  s.summary     = 'MonDupe'
  s.description = 'Create an AWS EC2 node and restore a MongoDB dump to it from an AWS S3 bucket'
  s.authors     = ["Philip Hutchins"]
  s.email       = 'flipture@gmail.com'
  s.files       = ["lib/mondupe.rb"]
  s.executables << 'mondupe'
  s.add_runtime_dependency 'aws-sdk', '~>1.38'
  s.homepage    = 'http://phutchins.com'
  s.license     = 'MIT'
end
