require "option_parser"

module Kube::Helper::Args
  def parse_args
    OptionParser.parse do |parser|
      parser.invalid_option do |flag|
        STDERR.puts "ERROR: #{flag} is not a valid option."
        STDERR.puts parser
        exit(1)
      end

      parser.banner = "Usage: kube-helper [arguments]"
      parser.separator
      parser.on("-h", "--help", "Show this help") do
        puts parser
        exit
      end

      parser.on("--version", "Print version and exit") do
        puts Kube::Helper::VERSION
        exit
      end

      parser.separator
      parser.separator("Config Flags:")
      parser.on("-w DIR", "--workdir DIR", "Working directory. default: \"./\"") { |dir| OPTIONS[:workdir] = File.expand_path(dir) }
      parser.on("-f FILE", "--file FILE", "Name of config file. default: deployment.yml") { |file| OPTIONS[:config_file] = file }
      parser.on("--kubeconfig FILE", "Path to the kube config file. default: #{OPTIONS[:kube_config]}") { |file| OPTIONS[:kube_config] = file }

      parser.separator
      parser.separator("Logging Flags:")
      parser.on("-q", "--quiet", "Log errors only") { OPTIONS[:quiet] = true }
      parser.on("-v", "--verbose", "Log verbose") { OPTIONS[:verbose] = true }
      parser.on("-d", "--debug", "Log debug") { OPTIONS[:debug] = true }

      parser.separator
      parser.separator("Runtime Flags:")

      # parser.separator
      parser.separator("  general options:")
      parser.on("--all", "Apply all updates/changes") { OPTIONS[:all] = true }
      parser.on("-l", "--list", "List groups and apps and exit") { OPTIONS[:list] = true }

      # parser.separator
      parser.separator("  apply/create specific resources:")
      parser.on("--ns", "--namespaces", "Create namespaces") { OPTIONS[:namespaces] = true }
      parser.on("-m", "--manifests", "Apply manifests") { OPTIONS[:manifests] = true }
      parser.on("-s", "--secrets", "Apply secrets") { OPTIONS[:secrets] = true }
      parser.on("-c", "--configmaps", "Apply configmaps") { OPTIONS[:config_maps] = true }

      # parser.separator
      parser.separator("  filter resources:")
      parser.on("--groups", "Update only groups") { OPTIONS[:groups] = true }
      parser.on("--apps", "Update only apps") { OPTIONS[:apps] = true }
      parser.on("-g NAME", "--group NAME",
        "Only apply changes to specified group with NAME. (accepts multiple)") do |name|
        OPTIONS[:group_names].as(Array(String)) << name
        OPTIONS[:groups] = true
      end
      parser.on("-n NAME", "--name NAME",
        "Only apply changes to apps with this name.       (accepts multiple)") do |name|
        OPTIONS[:name_filter] = true
        OPTIONS[:names].as(Array(String)) << name
      end

      # parser.separator
      parser.separator("  local environment config:")
      parser.on("--helm", "Update helm repos") { OPTIONS[:helm_repos] = true }

      # parser.separator
      parser.separator("  destructive actions:")
      parser.on("--delete", "Delete app manifests\n") { OPTIONS[:delete] = true }
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
