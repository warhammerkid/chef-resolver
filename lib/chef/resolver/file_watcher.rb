class Chef
  module Resolver
    class FileWatcher
      def initialize filenames
        self.filenames = filenames
      end

      def filenames= filenames
        @filenames = filenames || []
        @mtimes = {}
        @filenames.each do |f|
          raise "File does not exist: #{f}" unless File.exist?(f)
          @mtimes[f] = File.stat(f).mtime
        end
      end

      def watch &callback
        @thread = Thread.new { watch_filenames &callback }
      end

      def stop
        @thread.kill
      end

    private
      def watch_filenames &callback
        loop do
          sleep 1

          @filenames.each do |f|
            if File.exist?(f)
              mtime = File.stat(f).mtime
              next if @mtimes[f] == mtime
              @mtimes[f] = mtime
              yield f
            else
              yield f
              next
            end
          end
        end
      end
    end
  end
end