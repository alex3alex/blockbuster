module Blockbuster
  # Manages cassette packaging and unpackaging
  class Manager
    include Blockbuster::OutputHelpers

    attr_accessor :comparator

    def configuration
      @configuration ||= Blockbuster::Configuration.new
    end

    def initialize(instance_configuration = Blockbuster::Configuration.new)
      yield configuration if block_given?

      @configuration ||= instance_configuration

      @comparator      = Comparator.new(@configuration)
      @extraction_list = ExtractionList.new(@comparator, @configuration)
    end

    # extracts cassettes from a tar.gz file
    #
    # tracks a md5 hash of each file in the tarball
    def rent
      unless File.exist?(@extraction_list.master.file_path)
        silent_puts "File does not exist: #{@extraction_list.master.file_path}."
        return false
      end

      remove_existing_cassette_directory if configuration.wipe_cassette_dir

      silent_puts "Extracting VCR cassettes to #{configuration.cassette_dir}"

      @extraction_list.extract_cassettes

      @comparator.store_current_delta_files if configuration.deltas_enabled?
    end

    # repackages cassettes into a compressed tarball
    def drop_off(force: false)
      if comparator.rewind?(configuration.cassette_files) || force
        silent_puts "Recreating cassette file #{@extraction_list.primary.file_name}"
        @extraction_list.primary.create_cassette_file
      end
    end

    alias setup rent
    alias teardown drop_off

    private

    def remove_existing_cassette_directory
      return if configuration.local_mode

      dir = configuration.cassette_dir

      silent_puts "Wiping cassettes directory: #{dir}"
      FileUtils.rm_r(dir) if Dir.exist?(dir)
    end
  end
end
