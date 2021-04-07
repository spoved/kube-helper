require "tablo"
require "file_utils"
require "spoved/logger"
require "spoved/system_cmd"
require "./types"
require "./helper/*"

class Kube::Helper
  ::Log.builder.clear

  getter config : Config

  spoved_logger level: :info, bind: true

  include Spoved::SystemCmd
  include Kube::Helper::Args
  include Kube::Helper::Kubectl
  include Kube::Helper::Secrets
  include Kube::Helper::Apps
  include Kube::Helper::Helm
  include Kube::Helper::Group

  def initialize
    parse_args
    config_file = File.join(OPTIONS[:workdir].as(String), "deployment.yml")
    unless File.exists?(config_file)
      puts "ERROR: Config file #{config_file} does not exist"
      exit 1
    end

    @config = Config.from_yaml(File.read(config_file))
  end

  def opts
    OPTIONS
  end

  def opt(key : Symbol) : Bool | String | Nil | Array(String)
    OPTIONS[key]?
  end

  def workdir : String
    OPTIONS[:workdir].as(String)
  end

  def group_names
    OPTIONS[:group_names].as(Array(String))
  end

  def config
    @config
  end

  def run_cmd(cmd)
    result = system_cmd(cmd)
    raise "command failed: #{cmd}" unless result[:status]
    result
  end

  def get_path(sub_path)
    File.join(WORKDIR, sub_path)
  end

  ############
  # OTHER

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
    self.config.groups.each do |name, group|
      group.apps.each do |app|
        data << [name, app.name, (group.ignore || app.ignore).to_s, app.namespace]
      end
    end

    self.config.apps.each do |app|
      data << ["---", app.name, app.ignore.to_s, app.namespace]
    end
    pp data
    table = Tablo::Table.new(data, connectors: Tablo::CONNECTORS_SINGLE_ROUNDED) do |t|
      t.add_column("Group", &.[0])
      t.add_column("Name", &.[1])
      t.add_column("Namespace", &.[3])
      t.add_column("Ignored", &.[2])
    end

    table.shrinkwrap!
    puts table
    exit
  end

  def run!
    Dir.cd(workdir) do
      logger.trace &.emit "start", pwd: FileUtils.pwd
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
end
