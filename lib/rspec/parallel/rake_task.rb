require "rspec/parallel"

namespace :db do
  namespace :test do
    desc "Prepare sequence of databases for parallel-rspec"
    task :prepare_sequential, ["concurrency"] => :environment do |_, args|
      require "active_record/tasks/database_tasks"
      concurrency = Integer(args[:concurrency] || RSpec::Parallel.configuration.concurrency)

      concurrency.times do |i|
        database = ActiveRecord::Base.configurations["test"]["database"] + i.to_s
        configuration = ActiveRecord::Base.configurations["test"].merge("database" => database)

        ActiveRecord::Tasks::DatabaseTasks.drop(configuration) unless ENV["CI"]
        puts "Create and load schema to #{database}"
        ActiveRecord::Tasks::DatabaseTasks.create(configuration)
        stdout = $stdout
        begin
          $stdout = File.open(File::NULL, "w")
          ActiveRecord::Tasks::DatabaseTasks.load_schema(configuration)
        ensure
          $stdout = stdout
        end
      end
    end
  end
end
