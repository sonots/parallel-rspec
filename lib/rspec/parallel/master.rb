require "English"
require "fileutils"
require "rspec/core"
require "socket"

require_relative "errors"
require_relative "protocol"
require_relative "socket_builder"

module RSpec
  module Parallel
    class Master
      # @param args [Array<String>]
      attr_reader :args

      # @note RSpec must be configured ahead
      # @param args [Array<String>] command line arguments
      # @param configuration [RSpec::Core::Configuration]
      def initialize(args, configuration)
        @args = args
        @path = "/tmp/parallel-rspec-#{$PID}.sock"
        @files_to_run = configuration.files_to_run.uniq
        @total = @files_to_run.size
        @server = ::UNIXServer.new(@path)
      end

      # @return [void]
      def close
        server.close
      end

      # @return [void]
      def run
        count = 1
        until files_to_run.empty?
          rs, _ws, _es = IO.select([server])
          rs.each do |s|
            socket = s.accept
            method, data = socket.gets.strip.split(" ", 2)
            case method
            when Protocol::POP
              path = files_to_run.pop
              RSpec::Parallel.configuration.logger.info("[#{count} / #{total}] Deliver #{path} to worker[#{data}]")
              count += 1
              socket.write(path)
            when Protocol::PING
              socket.write("ok")
            end
            socket.close
          end
        end
        close
        remove_socket_file
      end

      # Create a socket builder which builds a socket to
      # connect with the master process.
      #
      # @return [RSpec::Parallel::SocketBuilder]
      def socket_builder
        SocketBuilder.new(path)
      end

      private

      # @return [String, nil] path to unix domain socket
      attr_reader :path

      # @example
      #   files_to_run
      #   #=> ["spec/rspec/parallel_spec.rb", "spec/rspec/parallel/configuration_spec.rb"]
      # @return [Array<String>]
      attr_reader :files_to_run

      # @return [UNIXServer]
      attr_reader :server

      # @return [Integer]
      attr_reader :total

      # @return [void]
      def remove_socket_file
        FileUtils.rm(path, force: true)
      end
    end
  end
end
