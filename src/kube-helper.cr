require "file_utils"
require "spoved/logger"
require "spoved/system_cmd"
require "option_parser"
require "http/request"
require "file"
require "./kube-helper/*"
require "tablo"

WORKDIR = FileUtils.pwd
OPTIONS = Hash(Symbol, Bool | String | Nil | Array(String)){
  :quiet       => false,
  :verbose     => false,
  :debug       => false,
  :all         => false,
  :manifests   => false,
  :namespaces  => false,
  :names       => Array(String).new,
  :name_filter => false,
  :secrets     => false,
  :config_maps => false,
  :apps        => false,
  :delete      => false,
  :groups      => false,
  :group_names => Array(String).new,
  :list        => false,
}

CONFIG     = Config.from_yaml(File.read(File.join(WORKDIR, "deployment.yml")))
KUBECONFIG = File.join(WORKDIR, "kube_config_cluster.yml")
KUBECMD    = "kubectl --kubeconfig #{KUBECONFIG}"

module Kube::Helper
  extend self
  ::Log.builder.clear

  spoved_logger level: :info, bind: true

  include Spoved::SystemCmd
  include Kube::Helper::Kubectl
  include Kube::Helper::Secrets
  include Kube::Helper::Apps
  include Kube::Helper::Helm
  include Kube::Helper::Group

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

  def opts
    OPTIONS
  end

  def opt(key : Symbol) : Bool | String | Nil | Array(String)
    OPTIONS[key]?
  end

  def group_names
    OPTIONS[:group_names].as(Array(String))
  end

  def config
    CONFIG
  end

  def logger
    Spoved::Log
  end

  def run_cmd(cmd)
    result = system_cmd(cmd)
    raise "command failed: #{cmd}" unless result[:status]
    result
  end

  def get_path(sub_path)
    File.join(WORKDIR, sub_path)
  end

  # ## OTHER

  def check_manifests
    logger.info { "Checking manifests" }
    config.manifests.each do |m|
      apply_manifest m
    end
  end

  def check_namespaces
    logger.info { "Checking namespaces" }
    config.namespaces.each do |ns|
      create_ns(ns)
    end
  end

  def check_apps
    config.apps.each do |options|
      if should_skip?(options)
        logger.warn { "skipping app #{options.name}" }
        next
      end
      logger.info { "Updating app definition: #{options.name}" }
      create_ns(options.namespace)
      apply_app(options)
    end
  end

  def check_config_maps
    return if config.config_maps.empty?
    logger.info { "Applying ConfigMaps" }
    config.config_maps.each do |s|
      apply_configmap s
    end
  end

  def check_secrets
    return if config.secrets.empty?
    logger.info { "Applying Secrets" }
    config.secrets.each do |s|
      apply_secret s
    end
  end

  def check_groups
    config.groups.each do |name, group|
      if !group_names.empty?
        next unless group_names.includes?(name)
        apply_group(name, group)
      else
        apply_group(name, group)
      end
    end
  end

  def list_apps
    data = Array(Array(String)).new
    config.groups.each do |name, group|
      group.apps.each do |app|
        data << [name, app.name, (group.ignore || app.ignore).to_s, app.namespace]
      end
    end

    config.apps.each do |app|
      data << ["---", app.name, app.ignore.to_s, app.namespace]
    end

    table = Tablo::Table.new(data, connectors: Tablo::CONNECTORS_SINGLE_ROUNDED) do |t|
      t.add_column("Group") { |n| n[0] }
      t.add_column("Name") { |n| n[1] }
      t.add_column("Namespace") { |n| n[3] }
      t.add_column("Ignored") { |n| n[2] }
    end

    table.shrinkwrap!
    puts table
    exit
  end

  def run
    parse_args

    list_apps if opt(:list)

    logger.info { "Start" }

    update_helm_repos if opt(:helm_repos)

    check_namespaces if opt(:namespaces) || opt(:all)
    check_secrets if opt(:secrets) || opt(:all)
    check_config_maps if opt(:config_maps) || opt(:all)
    check_apps if opt(:apps) || opt(:all)
    check_manifests if opt(:manifests) || opt(:all)

    check_groups if opt(:groups) || opt(:all)

    logger.info { "Done" }
  end
end

Kube::Helper.run
