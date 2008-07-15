require 'active_resource'
require 'tmpdir'
require 'fileutils'

module Registry
  class Extension < ActiveResource::Base
    self.site = ENV['REGISTRY_URL'] || "http://ext.radiantcms.org/"

    def install
      install_type.constantize.new(self).install
    end

    def uninstall
      Uninstaller.new(self).uninstall
    end
  end

  class Action
    def rake(command)
      `rake #{command} RAILS_ENV=#{RAILS_ENV}`
    end
  end

  class Installer < Action
    attr_accessor :url, :path, :name
    def initialize(url, name)
      self.url, self.name = url, name
    end

    def install
      copy_to_vendor_extensions
      migrate
      update
    end

    def copy_to_vendor_extensions
      FileUtils.cp_r(self.path, File.expand_path(File.join(RAILS_ROOT, 'vendor', 'extensions', name)))
      FileUtils.rm_r(self.path)
    end

    def migrate
      rake "radiant:extensions:#{name}:migrate"
    end

    def update
      rake "radiant:extensions:#{name}:update"
    end
  end

  class Uninstaller < Action
    attr_accessor :name
    def initialize(extension)
      self.name = extension.name
    end

    def uninstall
      migrate_down
      remove_extension_directory
      cleanup_environment
    end

    def migrate_down
      rake "radiant:extensions:#{name}:migrate VERSION=0"
    end

    def remove_extension_directory
      FileUtils.rm_r(File.join(RAILS_ROOT, 'vendor', 'extensions', name))
    end

    def cleanup_environment
      # Maybe in the future clear it out of the config.extensions array
    end
  end

  class Checkout < Installer
    def initialize(extension)
      super(extension.repository_url, extension.name)
    end

    def checkout_command
      raise "Not Implemented!"
    end

    def install
      checkout
      super
    end

    def checkout
      self.path = File.join(Dir.tmpdir, name)
      system "cd #{Dir.tmpdir}; #{checkout_command}"
    end
  end

  class Download < Installer
    def initialize(extension)
      super(extension.download_url, extension.name)
    end

    def install
      download
      unpack
      super
    end

    def unpack
      raise "Not Implemented!"
    end

    def filename
      File.basename(self.url)
    end

    def download
      require 'open-uri'
      File.open(File.join(Dir.tmpdir, self.filename), 'w') {|f| f.write open(self.url).read }
    end
  end

  class Git < Checkout
    def checkout_command
      "git clone #{url} #{name}"
    end

    def abstract?
      false
    end

    def matches?
      self.url =~ /\.?git/
    end
  end

  class Subversion < Checkout
    def checkout_command
      "svn checkout #{url} #{name}"
    end
  end

  class Gem < Download
    def download
      # Don't download the gem if it's already installed
      begin
        gem filename.split('-').first
      rescue ::Gem::LoadError
        super
        `gem install #{filename}`
      end
    end

    def unpack
      output = `cd #{Dir.tmpdir}; gem unpack #{filename.split('-').first}`
      self.path = output.match(/'(.*)'/)[1]
    end
  end

  class Tarball < Download
    def unpack
      packed  = filename =~ /gz/ ? 'z' : ''
      output = `cd #{Dir.tmpdir}; tar xvf#{packed} #{filename}`
      self.path = File.join(Dir.tmpdir, output.split(/\n/).first.split('/').first)
    end
  end

  class Zip < Download
    def unpack
      output = `cd #{Dir.tmpdir}; unzip #{filename} -d #{name}`
      self.path = File.join(Dir.tmpdir, name)
    end
  end
end

module Radiant
  class Extension
    module Script
      class << self
        def execute(args)
          command = args.shift || 'help'
          const_get(command.camelize).new(args)
        end
      end

      module Util
        attr_accessor :extension_name, :extension

        def to_extension_name(string)
          string.to_s.underscore
        end

        def installed?
          path_match = Regexp.compile("#{extension_name}$")
          extension_paths.any? {|p| p =~ path_match }
        end

        def extension_paths
          [RAILS_ROOT, RADIANT_ROOT].uniq.map { |p| Dir["#{p}/vendor/extensions/*"] }.flatten
        end

        def load_extensions
          Registry::Extension.find(:all)
        end

        def find_extension
          self.extension = load_extensions.find{|e| e.name == self.extension_name }
        end
      end

      class Install
        include Util

        def initialize(args=[])
          raise ArgumentError, "You must specify an extension to install." if args.blank?
          self.extension_name = to_extension_name(args.shift)
          if installed?
            puts "#{extension_name} is already installed."
          else
            find_extension && extension.install
          end
        end
      end

      class Uninstall
        include Util

        def initialize(args=[])
          raise ArgumentError, "You must specify an extension to uninstall." if args.blank?
          self.extension_name = to_extension_name(args.shift)
          if installed?
            find_extension && extension.uninstall
          else
            puts "#{extension} is not installed."
          end
        end
      end

      class Help
        include Util
        def initialize(args=[])
          helpcmd = args.shift || 'basic'
          send helpcmd
        end

        def basic
          output <<-HELP
          Usage: script/extension [command] [arguments]

            Commands:

              install     Install an extension from the registry.
              uninstall   Uninstall a previously installed extension.
              help        Display help for commands

          Type 'script/extension help [command]' for information about that
          command.
          HELP
        end
        alias :help :basic

        def install
          output <<-HELP
          Usage: script/extension install extension_name

            - Installs an extension from the information in the registry.

          HELP
        end

        def uninstall
          output <<-HELP
          Usage: script/extension uninstall extension_name

            - Uninstalls a previously installed extension.

          HELP
        end

        private
          def output(string='')
            $stdout.puts strip_leading_whitespace(string)
          end

          def strip_leading_whitespace(text)
            text = text.dup
            text.gsub!("\t", "  ")
            lines = text.split("\n")
            leading = lines.map do |line|
              unless line =~ /^\s*$/
                 line.match(/^(\s*)/)[0].length
              else
                nil
              end
            end.compact.min
            lines.inject([]) {|ary, line| ary << line.sub(/^[ ]{#{leading}}/, "")}.join("\n")
          end
      end
    end
  end
end
