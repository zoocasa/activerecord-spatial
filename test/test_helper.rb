# frozen_string_literal: true

require 'simplecov'

SimpleCov.command_name('Unit Tests')
SimpleCov.start do
  add_filter '/test/'
  add_filter '/.bundle/'
end

require 'rubygems'
require 'minitest/autorun'
require 'minitest/reporters'
require 'rails'
require 'active_support'
require 'active_support/core_ext/module/aliasing'
require 'active_support/dependencies'
require 'active_record'
require 'active_record/fixtures'
require 'active_record/test_case'
require 'logger'

require File.join(File.dirname(__FILE__), %w{ .. lib activerecord-spatial })

POSTGIS_PATHS = [
  ENV['POSTGIS_PATH'],
  '/opt/local/share/postgresql*/contrib/postgis-*',
  '/usr/share/postgresql*/contrib/postgis-*',
  '/usr/pgsql-*/share/contrib/postgis-*'
].compact

puts "ActiveRecordSpatial #{ActiveRecordSpatial::VERSION}"
puts "ActiveRecord #{Gem.loaded_specs['activerecord'].version}"
puts "Ruby #{RUBY_VERSION}-p#{RUBY_PATCHLEVEL} - #{RbConfig::CONFIG['RUBY_INSTALL_NAME']}"
puts "Geos library #{Geos::VERSION}" if defined?(Geos::VERSION)
puts "GEOS #{Geos::GEOS_VERSION}"
puts "GEOS extensions #{Geos::GEOS_EXTENSIONS_VERSION}"

if defined?(Geos::FFIGeos)
  puts "Using #{Geos::FFIGeos.geos_library_paths.join(', ')}"
end

ActiveSupport::TestCase.test_order = :random
ActiveRecord::Base.logger = Logger.new('debug.log') if ENV['ENABLE_LOGGER']

configurations = {}

%w{
  database.yml
  local_database.yml
}.each do |file|
  file = File.join('test', file)

  next unless File.exist?(file)

  configuration = YAML.safe_load(File.read(file))

  configurations.merge!(configuration)

  if configuration['arunit']
    configurations['arunit'].merge!(configuration['arunit'])
  end

  if defined?(JRUBY_VERSION) && configuration['jdbc']
    configurations['arunit'].merge!(configuration['jdbc'])
  end
end

ActiveRecord::Base.configurations = configurations
ActiveRecord::Base.establish_connection :arunit
ARBC = ActiveRecord::Base.connection

postgresql_version = ARBC.select_rows('SELECT version()').first.first

if postgresql_version.present?
  puts "PostgreSQL info from version(): #{postgresql_version}"
end

puts 'Checking for PostGIS install'
2.times do
  postgis_version = ActiveRecordSpatial::POSTGIS[:lib]

  if postgis_version.present?
    puts "PostGIS info from postgis_full_version(): #{postgis_version}"
    break
  end
rescue ActiveRecord::StatementInvalid, PG::UndefinedFunction
  puts "Trying to install PostGIS. If this doesn't work, you'll have to do this manually!"

  ARBC.enable_extension('plpgsql') unless ARBC.extension_enabled?('plpgsql')
  ARBC.enable_extension('postgis') unless ARBC.extension_enabled?('postgis')
end

class ActiveRecordSpatialTestCase < ActiveRecord::TestCase
  BASE_PATH = Pathname.new(File.dirname(__FILE__))

  include ActiveRecord::TestFixtures
  self.fixture_path = BASE_PATH.join('fixtures')

  REGEXP_WKB_HEX = /[A-Fa-f0-9\s]+/.freeze

  POINT_WKT = 'POINT(10 10.01)'
  POINT_EWKT = 'SRID=4326; POINT(10 10.01)'
  POINT_EWKT_WITH_DEFAULT = 'SRID=default; POINT(10 10.01)'
  POINT_WKB = '0101000000000000000000244085EB51B81E052440'
  POINT_WKB_BIN = "\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x24\x40\x85\xEB\x51\xB8\x1E\x05\x24\x40"
  POINT_EWKB = '0101000020E6100000000000000000244085EB51B81E052440'
  POINT_EWKB_BIN = "\x01\x01\x00\x00\x20\xE6\x10\x00\x00\x00\x00\x00\x00\x00\x00\x24\x40\x85\xEB\x51\xB8\x1E\x05\x24\x40"
  POINT_G_LAT_LNG = '(10.01, 10)'
  POINT_G_LAT_LNG_URL_VALUE = '10.01,10'

  POLYGON_WKT = 'POLYGON((0 0, 1 1, 2.5 2.5, 5 5, 0 0))'
  POLYGON_EWKT = 'SRID=4326; POLYGON((0 0, 1 1, 2.5 2.5, 5 5, 0 0))'

  POLYGON_WKB = '
    0103000000010000000500000000000000000000000000000000000000000000000000F
    03F000000000000F03F0000000000000440000000000000044000000000000014400000
    00000000144000000000000000000000000000000000
  '.gsub(/\s/, '')

  POLYGON_WKB_BIN = [
    "\x01\x03\x00\x00\x00\x01\x00\x00\x00\x05\x00\x00\x00\x00\x00\x00\x00\x00\x00",
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xF0\x3F\x00",
    "\x00\x00\x00\x00\x00\xF0\x3F\x00\x00\x00\x00\x00\x00\x04\x40\x00\x00\x00\x00",
    "\x00\x00\x04\x40\x00\x00\x00\x00\x00\x00\x14\x40\x00\x00\x00\x00\x00\x00\x14",
    "\x40\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
  ].join

  POLYGON_EWKB = '
    0103000020E610000001000000050000000000000000000000000000000000000000000
    0000000F03F000000000000F03F00000000000004400000000000000440000000000000
    1440000000000000144000000000000000000000000000000000
  '.gsub(/\s/, '')

  POLYGON_EWKB_BIN = [
    "\x01\x03\x00\x00\x20\xE6\x10\x00\x00\x01\x00\x00\x00\x05\x00\x00\x00",
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
    "\x00\x00\x00\x00\x00\xF0\x3F\x00\x00\x00\x00\x00\x00\xF0\x3F\x00\x00",
    "\x00\x00\x00\x00\x04\x40\x00\x00\x00\x00\x00\x00\x04\x40\x00\x00\x00",
    "\x00\x00\x00\x14\x40\x00\x00\x00\x00\x00\x00\x14\x40\x00\x00\x00\x00",
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
  ].join

  POLYGON_WITH_INTERIOR_RING = 'POLYGON((0 0, 5 0, 5 5, 0 5, 0 0),(4 4, 4 1, 1 1, 1 4, 4 4))'

  LINESTRING_WKT = 'LINESTRING (0 0, 5 5, 5 10, 10 10)'

  GEOMETRYCOLLECTION_WKT = 'GEOMETRYCOLLECTION (
    MULTIPOLYGON (
      ((0 0, 1 0, 1 1, 0 1, 0 0)),
      (
        (10 10, 10 14, 14 14, 14 10, 10 10),
        (11 11, 11 12, 12 12, 12 11, 11 11)
      )
    ),
    POLYGON ((0 0, 1 0, 1 1, 0 1, 0 0)),
    POLYGON ((0 0, 5 0, 5 5, 0 5, 0 0), (4 4, 4 1, 1 1, 1 4, 4 4)),
    MULTILINESTRING ((0 0, 2 3), (10 10, 3 4)),
    LINESTRING (0 0, 2 3),
    MULTIPOINT ((0 0), (2 3)),
    POINT (9 0)
  )'

  BOUNDS_G_LAT_LNG = '((0.1, 0.1), (5.2, 5.2))'
  BOUNDS_G_LAT_LNG_URL_VALUE = '0.1,0.1,5.2,5.2'

  def load_models(*args)
    args.each do |model|
      require_dependency(BASE_PATH.join("models/#{model}.rb"))
    end
  end

  def load_default_models
    load_models(:foo, :bar)

    Foo.class_eval do
      has_many_spatially :foos
      has_many_spatially :bars
    end

    Bar.class_eval do
      has_many_spatially :foos
      has_many_spatially :bars
    end
  end

  def setup
    return unless ActiveRecord::Base.logger

    ActiveRecord::Base.logger.debug("Beginning tests for #{self.class.name}##{method_name}")
  end

  def assert_saneness_of_point(point)
    assert_kind_of(Geos::Point, point)
    assert_equal(10.01, point.lat)
    assert_equal(10, point.lng)
  end

  def assert_saneness_of_polygon(polygon)
    assert_kind_of(Geos::Polygon, polygon)
    cs = polygon.exterior_ring.coord_seq
    assert_equal([
      [0, 0],
      [1, 1],
      [2.5, 2.5],
      [5, 5],
      [0, 0]
    ], cs.to_a)
  end

  def reflection_key(key)
    key.to_s
  end
end

class SpatialTestRunner < Minitest::Reporters::SpecReporter
  # no-op
end

Minitest::Reporters.use!(SpatialTestRunner.new, ENV, Minitest::ExtensibleBacktraceFilter.default_filter)

require './test/schema'

ActiveRecord::FixtureSet.create_fixtures("#{__dir__}/fixtures", Dir.glob("#{__dir__}/fixtures/*.yml").collect { |file| File.basename(file).gsub(/.yml$/, '') })
