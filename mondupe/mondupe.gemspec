Gem::Specification.new do |s|
  s.name        = 'mondupe'
  s.version     = '0.0.1'
  s.date        = '2014-04-25'
  s.summary     = 'MonDupe'
  s.description = 'Create an AWS EC2 node and restore a MongoDB dump to it from an AWS S3 bucket'
  s.authors     = ["Philip Hutchins"]
  s.email       = 'flipture@gmail.com'
  s.files       = ["lib/mondupe.rb"]
  s.executables << 'mondupe'
  s.add_runtime_dependency 'aws-sdk', '~>1.38.0'
  s.homepage    = 'http://phutchins.com'
  s.license     = 'MIT'
end
