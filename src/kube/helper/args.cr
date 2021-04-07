require "option_parser"

module Kube::Helper::Args
  def parse_args
    OptionParser.parse do |parser|
      parser.banner = "Usage: crystal update.cr -- [arguments]"
      parser.on("-h", "--help", "Show this help") do
        puts parser
        exit
      end

      # logging options
      parser.on("-q", "--quiet", "Log errors only") { OPTIONS[:quiet] = true }
      parser.on("-v", "--verbose", "Log verbose") { OPTIONS[:verbose] = true }
      parser.on("-d", "--debug", "Log debug") { OPTIONS[:debug] = true }
      parser.on("-l", "--list", "List groups and apps") { OPTIONS[:list] = true }

      # run mode options
      parser.on("--all", "Apply all updates/changes") { OPTIONS[:all] = true }
      parser.on("-m", "--manifests", "Apply manifests") { OPTIONS[:manifests] = true }
      parser.on("--ns", "--namespaces", "Create namespaces") { OPTIONS[:namespaces] = true }
      parser.on("--helm", "Update helm repos") { OPTIONS[:helm_repos] = true }

      parser.on("-s", "--secrets", "Apply secrets") { OPTIONS[:secrets] = true }
      parser.on("-c", "--configmaps", "Apply configmaps") { OPTIONS[:config_maps] = true }

      parser.on("--groups", "Update groups") { OPTIONS[:groups] = true }
      parser.on("--apps", "Update apps") { OPTIONS[:apps] = true }
      parser.on("--delete", "Delete app manifests") { OPTIONS[:delete] = true }

      parser.on("-w DIR", "--workdir DIR", "Work directory") { |dir| OPTIONS[:workdir] = File.expand_path(dir) }

      parser.on("-g NAME", "Update specified group with NAME") do |name|
        OPTIONS[:group_names].as(Array(String)) << name
        OPTIONS[:groups] = true
      end
      # filtering options
      parser.on("-n NAME", "--name=NAME", "Only apply changes to apps with this name") do |name|
        OPTIONS[:name_filter] = true
        OPTIONS[:names].as(Array(String)) << name
      end

      parser.invalid_option do |flag|
        STDERR.puts "ERROR: #{flag} is not a valid option."
        STDERR.puts parser
        exit(1)
      end
    end

    if OPTIONS[:verbose]
      logger.level = :trace
    elsif OPTIONS[:debug]
      logger.level = :debug
    elsif OPTIONS[:quiet]
      logger.level = :error
    end

    logger.trace { OPTIONS.to_s }
  end
end
