require 'pry'
require 'spec_helper'

describe Blockbuster do
  it 'has a version number' do
    Blockbuster::VERSION.wont_be_nil
  end

  describe 'Blockbuster::Manager' do
    let(:klass) { Blockbuster::Manager }

    describe 'constructor' do
      let(:cass_dir)  { '/foo/bar' }
      let(:cass_file) { 'betamax.tar.gz' }
      let(:tst_dir)   { 'zspec' }

      it 'has default attributes' do
        manager = klass.new

        manager.cassette_directory.must_equal klass::CASSETTE_DIRECTORY
        manager.cassette_file.must_equal klass::CASSETTE_FILE
        manager.local_mode.must_equal false
        manager.test_directory.must_equal klass::TEST_DIRECTORY
        manager.silent.must_equal false
        manager.wipe_cassette_dir.must_equal klass::WIPE_CASSETTE_DIR
      end

      it 'can be intialized with attributes' do
        mgr = klass.new(cassette_directory: cass_dir)
        mgr.cassette_directory.must_equal cass_dir

        mgr = klass.new(cassette_file: cass_file)
        mgr.cassette_file.must_equal cass_file

        mgr = klass.new(silent: true)
        mgr.silent.must_equal true

        mgr = klass.new(test_directory: tst_dir)
        mgr.test_directory.must_equal tst_dir

        mgr = klass.new(wipe_cassette_dir: false)
        mgr.wipe_cassette_dir.must_equal false
      end

      it 'can set @silent' do
        mgr = klass.new(silent: true)
        mgr.silent.must_equal true

        mgr.silent = false
        mgr.silent.must_equal false
      end

      it 'initializes with an empty comparison_hash' do
        manager = klass.new
        manager.comparison_hash.must_equal({})
      end
    end

    describe 'instance methods' do
      let(:my_test_dir)       { File.join(File.dirname(__FILE__), 'fixtures') }
      let(:cassette_dir)      { 'cassettes' }
      let(:cassette_dir_path) { File.join(my_test_dir, 'cassettes') }
      let(:cassette_1)        { File.join(cassette_dir_path, 'match_requests_on.yml') }
      let(:cassette_2)        { File.join(cassette_dir_path, 'fake_example_response.yml') }
      let(:manager) do
        klass.new(test_directory: my_test_dir,
                  cassette_file: 'test_cassettes.tar.gz',
                  cassette_directory: cassette_dir,
                  silent: true)
      end

      after do
        ENV['VCR_MODE'] = nil
        FileUtils.rm_r(cassette_dir_path) if Dir.exist?(cassette_dir_path)
      end

      describe '.rent' do
        it 'does nothing if ENV["VCR_MODE"] equals "local"' do
          ENV['VCR_MODE'] = 'local'
          manager.rent

          Dir.exist?(cassette_dir).must_equal false
        end

        it 'returns false if the cassette file does not exists' do
          manager = klass.new(cassette_file: 'nosuchfile.tar.gz', silent: true)

          manager.rent.must_equal false
        end

        it 'extracts cassette files' do
          manager.cassette_file.must_equal 'test_cassettes.tar.gz'
          manager.rent

          File.exist?(cassette_1).must_equal true
          File.exist?(cassette_2).must_equal true
          FileUtils.identical?(cassette_1, File.join(my_test_dir, 'match_requests_on.yml')).must_equal true
          FileUtils.identical?(cassette_2, File.join(my_test_dir, 'fake_example_response.yml')).must_equal true
        end

        it 'has an alias' do
          manager.must_respond_to :setup
        end

        it 'tracks a hash of each file for comparison upon teardown' do
          manager.rent

          manager.comparison_hash.keys.must_include 'cassettes/match_requests_on.yml'
          manager.comparison_hash.keys.must_include 'cassettes/fake_example_response.yml'
        end

        describe 'wipe_cassette_dir option' do
          before do
            manager.cassette_file.must_equal 'test_cassettes.tar.gz'
            manager.rent
            FileUtils.touch(File.join(cassette_dir_path, 'fakefile'))
          end

          it 'wipes the existing cassette directory if wipe_cassette_dir is true' do
            manager.wipe_cassette_dir.must_equal true

            manager.rent

            File.exist?(File.join(cassette_dir_path, 'fakefile')).must_equal false
          end

          it 'does not wipe the cassette directory if local_mode is true' do
            manager.instance_variable_set(:@local_mode, true)

            manager.rent

            File.exist?(File.join(cassette_dir_path, 'fakefile')).must_equal true
          end

          it 'leaves the cassete directory as is if wipe_cassette_dir is false' do
            manager.instance_variable_set(:@wipe_cassette_dir, false)

            manager.rent

            File.exist?(File.join(cassette_dir_path, 'fakefile')).must_equal true
          end
        end
      end

      describe '.drop_off' do
        let(:cass)      { manager.send(:cassette_file_path) }
        let(:orig_cass) { "#{cass}.tmp" }

        before do
          manager.rent
          FileUtils.cp(cass, orig_cass, preserve: true)
        end

        after do
          FileUtils.mv(orig_cass, cass)
        end

        it 'does nothing if there were no changes' do
          manager.drop_off

          FileUtils.identical?(cass, orig_cass).must_equal true
          File.mtime(cass).must_be :==, File.mtime(orig_cass)
        end

        it 'creates a new cassette file if force is true' do
          manager.silent = false
          proc { manager.drop_off(force: true) }.must_output(/Recreating cassette file/)

          File.mtime(cass).must_be :!=, File.mtime(orig_cass)
        end

        it 'creates a new cassette file if rewind? is true' do
          open(cassette_2, 'a') do |file|
            file << 'new recording'
          end
          manager.silent = false
          proc { manager.drop_off(force: true) }.must_output(/Recreating cassette file/)

          FileUtils.identical?(cass, orig_cass).must_equal false
          File.mtime(cass).must_be :!=, File.mtime(orig_cass)
        end
      end

      describe '.rewind?' do
        before do
          manager.rent
        end

        it 'returns false if no files have changed' do
          manager.rewind?.must_equal false
        end

        it 'returns true if a cassette file was changed' do
          open(cassette_2, 'a') do |file|
            file << 'new recording'
          end
          manager.silent = false
          proc { manager.rewind?.must_equal true }.must_output(/Cassette changed: /)
        end

        it 'returns true if no comparison_hash was created' do
          manager.comparison_hash = {}
          manager.silent = false
          proc { manager.rewind?.must_equal true }.must_output(/New cassette: /)
        end

        it 'returns false if a file was deleted from the cassettes directory' do
          FileUtils.rm(cassette_1)
          manager.silent = false
          proc { manager.rewind?.must_equal true }.must_output(/Cassettes deleted: /)
        end

        it 'returns false if a file was added to the cassettes directory' do
          new_cass = File.join(cassette_dir_path, 'new_cass.yml')
          FileUtils.touch(new_cass)
          manager.silent = false
          proc { manager.rewind?.must_equal true }.must_output(/New cassette: /)
        end
      end
    end
  end
end
