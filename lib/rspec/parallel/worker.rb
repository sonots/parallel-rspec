require_relative "protocol"

module RSpec
  module Parallel
    class Worker
      # @return [Integer]
      attr_reader :number

      # @param master [RSpec::Parallel::Master]
      # @param number [Integer]
      def initialize(master, number)
        RSpec::Parallel.configuration.logger.debug("Initialize Loader")
        @loader = Loader.new(self, master.socket_builder)
        @number = number
        RSpec::Parallel.configuration.logger.debug("Initialize SpecRunner")
        @spec_runner = SpecRunner.new(master.args)
      end

      # @return [void]
      def run
        loader.ping
        loader.load_example_groups
        spec_runner.run_specs(RSpec.world.ordered_example_groups).to_i
      end

      private

      attr_reader :loader, :spec_runner

      class Loader
        # @param worker [RSpec::Parallel::Worker]
        # @param socket_builder [RSpec::Parallel::SocketBuilder]
        def initialize(worker, socket_builder)
          @worker = worker
          @socket_builder = socket_builder
        end

        # @return [void]
        def ping
          loop do
            socket = connect_to_distributor
            if socket.nil?
              RSpec::Parallel.configuration.logger.debug("Sleep a little to wait master process")
              sleep 0.5
              next
            end
            RSpec::Parallel.configuration.logger.debug("Send PING request")
            socket.puts(Protocol::PING)
            # TODO: handle socket error and check pong message
            IO.select([socket])
            socket.read(65_536)
            socket.close
            break
          end
        end

        # @return [void]
        def load_example_groups
          loop do
            socket = connect_to_distributor
            break if socket.nil?
            RSpec::Parallel.configuration.logger.debug("Send POP request")
            socket.puts("#{Protocol::POP} #{worker.number}") # TODO: Rescue `Broken pipe (Errno::EPIPE)` error
            _, _, es = IO.select([socket], nil, [socket])
            unless es.empty?
              RSpec::Parallel.configuration.logger.error("Socket error occurs")
              break
            end
            path = socket.read(65_536)
            socket.close
            RSpec::Parallel.configuration.logger.debug("Load #{path}")
            Kernel.load path
          end
        end

        private

        # @return [RSpec::Parallel::SocketBuilder]
        attr_reader :socket_builder

        # @return [RSpec::Parallel::Worker]
        attr_reader :worker

        # @return [BasicSocket, nil]
        def connect_to_distributor
          socket_builder.run
        end
      end

      class SpecRunner < RSpec::Core::Runner
        # @param args [Array<String>]
        def initialize(args)
          options = RSpec::Core::ConfigurationOptions.new(args)
          super(options)
        end

        # @param example_groups [Array<RSpec::Core::ExampleGroup>]
        # @return [Integer] exit status code
        def run_specs(example_groups)
          @world.announce_filters
          examples_count = @world.example_count(example_groups)

          success = @configuration.reporter.report(examples_count) do |reporter|
            # In genaral, ExampleGroup is configured by evaluating `describe`
            # before `with_suite_hooks`
            RSpec::Core::ExampleGroup.ensure_example_groups_are_configured

            @configuration.with_suite_hooks do
              example_groups.map do |g|
                RSpec::Parallel.configuration.logger.debug("Run #{g.inspect}")
                g.run(reporter)
              end.all?
            end
          end && !@world.non_example_failure

          success ? 0 : @configuration.failure_exit_code
        end
      end
    end
  end
end
