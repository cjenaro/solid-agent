Gem::Specification.new do |spec|
  spec.name = 'solid_agent'
  spec.version = '0.2.0'
  spec.authors = ['Solid Agent']
  spec.summary = 'A plug-and-play Rails engine for agentic capabilities using the Solid stack'
  spec.description = 'Zero-config agent framework backed by SQLite, Solid Queue, and Solid Cable'
  spec.license = 'MIT'

  spec.files = Dir.glob('{app,config,db,lib}/**/*') + %w[README.md]
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 3.3.0'

  spec.add_dependency 'rails', '>= 8.0'
  spec.add_dependency 'solid_queue', '>= 1.0'

  spec.add_development_dependency 'minitest', '~> 5.0'
  spec.add_development_dependency 'sqlite3', '~> 2.0'
end
