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

      # @return [void]
      def start
        RSpec::Parallel.configuration.concurrency.times do
          spawn_worker
        end
        master.run
        Process.waitall

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
          worker = Worker.new(master, pids.size)
          $0 = "rspec-parallel worker [#{worker.number}]"
          RSpec::Parallel.configuration.after_fork_block.call(worker)

          File.open(output_file_path($PID), "w") do |file|
            # Redirect stdout and stderr to temp file
            $stdout.reopen(file)
            $stderr.reopen($stdout)
            $stdout.sync = $stderr.sync = true
            worker.run
          end

          Kernel.exit! # avoid running any `at_exit` functions.
        end
        pids << pid
        Process.detach(pid)
      end

      # @param pid [Integer]
      # @return [String]
      def output_file_path(pid)
        "/tmp/rspec-parallel-worker-#{pid}"
      end

      def configure_rspec
        options = ::RSpec::Core::ConfigurationOptions.new(args)
        options.configure(::RSpec.configuration)
      end
    end
  end
end
