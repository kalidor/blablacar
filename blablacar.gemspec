Gem::Specification.new do |s|
  s.name = 'blablacar'
  s.version = '0.1'
  s.executables << 'blablacar'
  s.date = '2017-04-05'
  s.summary = 'blablacar command line library'
  s.description = 'blablacar command line to interact with your account on blablacar.fr'
  s.authors = ["Gregory 'kalidor' CHARBONNEAU"]
  s.email = 'kalidor@unixed.fr'
  s.files = [ 'lib/libblablacar.rb',
  'lib/libblablacar/errors.rb',
  'lib/libblablacar/helpers.rb',
  'lib/libblablacar/consts.rb',
  'lib/libblablacar/notifications.rb',
  'lib/libblablacar/requests.rb']
  s.homepage = 'https://github.com/kalidor/blablacar'
  s.license = 'WTFPL'
  s.require_path = 'lib'
end
