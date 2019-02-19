require "English"

require_relative "master"
require_relative "worker"

module RSpec
  module Parallel
    class Runner
      # @return [Array<Integer>] array of pids of spawned worker processes
      attr_reader :pids

      # @param args [Array<String>] command line arguments
      def initialize(args)
        @args = args
        @pids = []

        # Configure RSpec core before initialize master instance and spawning
        # worker processes to share its configuration.
        configure_rspec
        @master = Master.new(args)
      end

      # @return [Integer] exit status code
      def start
        waiters = []
        RSpec::Parallel.configuration.concurrency.times do
          waiters << spawn_worker
        end
        master.run
        statuses = waiters.map {|waiter| waiter.value }
        statuses.all? {|status| status.success? } ? 0 : 1
      ensure
        pids.each.with_index do |pid, index|
          puts "----> output from worker[#{index}]"
          File.open(output_file_path(pid)) do |file|
            puts file.read
          end
        end
      end

      private

      # @return [Array<String>]
      attr_reader :args

      # @return [RSpec::Parallel::Master]
      attr_reader :master

      # @param master [RSpec::Parallel::Master]
      def spawn_worker
        pid = Kernel.fork do
          master.close

          exit_code = File.open(output_file_path($PID), "w") do |file|
            # Redirect stdout and stderr to temp file
            STDOUT.reopen(file)
            STDERR.reopen(STDOUT)
            STDOUT.sync = STDERR.sync = true

            worker = Worker.new(master, pids.size)
            $0 = "parallel-rspec worker [#{worker.number}]"
            RSpec::Parallel.configuration.after_fork_block.call(worker)
            worker.run
          end

          Kernel.exit!(exit_code == 0) # avoid running any `at_exit` functions.
        end
        pids << pid
        Process.detach(pid)
      end

      # @param pid [Integer]
      # @return [String]
      def output_file_path(pid)
        "/tmp/parallel-rspec-worker-#{pid}"
      end

      def configure_rspec
        options = ::RSpec::Core::ConfigurationOptions.new(args)
        options.configure(::RSpec.configuration)
      end
    end
  end
end
