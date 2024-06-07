require "tablo"
require "file_utils"
require "spoved/logger"
require "spoved/system_cmd"
require "./types"
require "./helper/*"

OPTIONS = Hash(Symbol, Bool | String | Nil | Array(String)){
  :quiet           => false,
  :verbose         => false,
  :debug           => false,
  :all             => false,
  :manifests       => false,
  :namespaces      => false,
  :names           => Array(String).new,
  :name_filter     => false,
  :secrets         => false,
  :config_maps     => false,
  :apps            => false,
  :delete          => false,
  :groups          => false,
  :kustomize       => false,
  :group_names     => Array(String).new,
  :list            => false,
  :workdir         => "./",
  :config_file     => "deployment.yml",
  :kube_config     => ENV.fetch("KUBECONFIG", File.join(Path.home, ".kube/config")),
  :kube_bin        => "kubectl",
  :helm_bin        => "helm",
  :context         => nil,
  :dry_run         => false,
  :server_side     => false,
  :force_conflicts => false,
}

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
    find_bins

    config_file = File.join(OPTIONS[:workdir].as(String), OPTIONS[:config_file].as(String))

    # Try to find `deployment.yaml` if `deployment.yml` is not found
    if OPTIONS[:config_file].as(String) == "deployment.yml" && !File.exists?(config_file)
      config_file = File.join(OPTIONS[:workdir].as(String), "deployment.yaml")
    end

    unless File.exists?(config_file)
      puts "ERROR: Config file #{config_file} does not exist"
      exit 1
    end

    @config = Config.from_yaml(File.read(config_file))
    @config.groups.each do |group|
      group.apps.each do |app|
        app.namespace = group.namespace.name if app.namespace.nil?
      end
    end
  end

  def find_bins
    ENV.fetch("PATH", "").split(":").each do |path|
      if File.exists?(File.join(path, "kubectl"))
        OPTIONS[:kube_bin] = File.join(path, "kubectl")
      end
      if File.exists?(File.join(path, "helm"))
        OPTIONS[:helm_bin] = File.join(path, "helm")
      end
    end

    logger.debug { "using kubectl: #{OPTIONS[:kube_bin]}" }
    logger.debug { "using helm: #{OPTIONS[:helm_bin]}" }
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

  def kube_context : String?
    (opt(:context) || @config.context).as(String?)
  end

  def dry_run? : Bool
    opt(:dry_run).as(Bool)
  end

  def config
    @config
  end

  def run_cmd(cmd, args)
    logger.debug { "running: #{cmd} #{args.join(" ")}" }
    result = system_cmd(cmd, args)
    raise "command failed: #{cmd} #{args.join(" ")}" unless result[:status]
    result
  end

  def parse_cmd(cmd)
    parts = cmd.split(/("[^"]+"|[^\s"]+)/).map!(&.chomp(' ')).reject(&.empty?)
    {parts.shift, parts}
  end

  def get_path(sub_path)
    File.join(self.workdir, sub_path)
  end

  ########################
  # Main run functions

  def check_manifests(ks_path : String)
    logger.info { "Checking manifests" }
    config.manifests.each do |m|
      apply_manifest m, ks_path
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
      apply_app(options)
    end
  end

  def check_config_maps(ks_path : String)
    return if config.config_maps.empty?
    logger.info { "Applying ConfigMaps" }
    config.config_maps.each do |s|
      apply_configmap s, ks_path
    end
  end

  def check_secrets(ks_path : String)
    return if config.secrets.empty?
    logger.info { "Applying Secrets" }
    config.secrets.each do |s|
      apply_secret s, ks_path
    end
  end

  def check_groups
    config.groups.each do |group|
      if !group_names.empty?
        next unless group_names.includes?(group.name)
        apply_group(group)
      else
        apply_group(group)
      end
    end
  end

  def check_kustomize
    return if config.kustomize.empty?
    logger.info { "start kustomize" }
    config.kustomize.each do |k|
      next if should_skip?(k)
      logger.info { "applying kustomize: #{k.name}" }
      ks = Kube::Helper::Kustomize.build_kustomization(k.name, "root", config.annotations)
      Kube::Helper::Kustomize.with_kustomize(ks) do |ks_path|
        apply_kustomize(k, ks_path)
      end
    end
  end

  def list_kustomize
    data = Array(Array(String)).new
    filler = "---"
    config.kustomize.each do |k|
      next if should_skip?(k)
      data << [k.name, k.namespace || filler, k.path]
    end

    table = Tablo::Table.new(data, connectors: Tablo::CONNECTORS_SINGLE_ROUNDED) do |t|
      t.add_column("Name", &.[0])
      t.add_column("Namespace", &.[1])
      t.add_column("Path", &.[2])
    end

    table.shrinkwrap!
    puts table
  end

  def list_apps
    data = Array(Array(String)).new
    filler = "---"

    # List top level apps
    self.config.apps.each do |app|
      next if should_skip?(app)
      if app.namespace.nil?
        raise "Namespace is required for apps defined on top level"
      end

      data << [filler, app.name, app.ignore.to_s, app.namespace.not_nil!]
    end

    # List groups and group apps
    self.config.groups.each do |group|
      next if !group_names.empty? && !group_names.includes?(group.name)

      data << [group.name, filler, group.ignore.to_s, group.namespace.name]
      group.apps.each do |app|
        next if should_skip?(app)

        ns = app.namespace!
        data << [group.name, app.name, (group.ignore || app.ignore).to_s, ns]
      end
    end

    table = Tablo::Table.new(data, connectors: Tablo::CONNECTORS_SINGLE_ROUNDED) do |t|
      t.add_column("Group", &.[0])
      t.add_column("Name", &.[1])
      t.add_column("Namespace", &.[3])
      t.add_column("Ignored", &.[2])
    end

    table.shrinkwrap!
    puts table
  end

  def run!
    Dir.cd(workdir) do
      logger.trace &.emit "start", pwd: FileUtils.pwd
      if opt(:list)
        puts "Kustomize:"
        list_kustomize
        puts ""
        puts "Apps:"
        list_apps
        exit
      end

      logger.info { "Start" }

      context = config.context
      if context
        logger.info { "setting context #{context}" }
        kubectl("config", "use-context", context.not_nil!.as(String))
      end

      update_helm_repos if opt(:helm_repos)

      ks = Kube::Helper::Kustomize.build_kustomization(nil, "root", config.annotations)
      Kube::Helper::Kustomize.with_kustomize(ks) do |ks_path|
        check_namespaces if opt(:namespaces) || opt(:all)
        check_secrets(ks_path) if opt(:secrets) || opt(:all)
        check_config_maps(ks_path) if opt(:config_maps) || opt(:all)
        check_manifests(ks_path) if opt(:manifests) || opt(:all)
        check_kustomize if opt(:kustomize) || opt(:all)
        check_apps if opt(:apps) || opt(:all)
        check_groups if opt(:groups) || opt(:all)
      end
      logger.info { "Done" }
    end
  end
end
