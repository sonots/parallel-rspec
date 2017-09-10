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

        configuration = RSpec::Core::Configuration.new
        configure_rspec(configuration)
        @master = Master.new(args, configuration)
      end

      # @return [void]
      def start
        RSpec::Parallel.configuration.concurrency.times do
          spawn_worker
        end
        master.run
        Process.waitall
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

      # @return [void]
      def spawn_worker
        pid = Kernel.fork do
          master.close

          File.open(output_file_path($PID), "w") do |file|
            # Redirect stdout and stderr to temp file
            STDOUT.reopen(file)
            STDERR.reopen(STDOUT)
            STDOUT.sync = STDERR.sync = true

            worker = Worker.new(master, pids.size)
            $0 = "parallel-rspec worker [#{worker.number}]"
            # TEST_ENV_NUMBER is used by parallel_tests
            ENV["PARALLEL_RSPEC_WORKER_NUMBER"] = ENV["TEST_ENV_NUMBER"] = worker.number.to_s
            RSpec::Parallel.configuration.after_fork_block.call(worker)
            configure_rspec(::RSpec.configuration)
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
        "/tmp/parallel-rspec-worker-#{pid}"
      end

      def configure_rspec(configuration)
        options = ::RSpec::Core::ConfigurationOptions.new(args)
        options.configure(configuration)
      end
    end
  end
end
