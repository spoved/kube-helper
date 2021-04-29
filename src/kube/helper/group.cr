module Kube::Helper::Group
  def is_helm_app?(options : AppOptions) : Bool
    !(options.chart.nil? && options.chart_url.nil? && options.chart_path.nil?)
  end

  def apply_group(group : ::Group)
    name = group.name
    if group.ignore
      logger.warn { "ignoring group: #{name}" }
      return
    end

    namespace = group.namespace

    logger.info { "group: #{name} - checking namespace" }
    create_ns(namespace)

    unless group.secrets.empty?
      logger.info { "group: #{name} - applying secrets" }
      group.secrets.each do |secret|
        apply_secret(secret)
      end
    end

    unless group.config_maps.empty?
      logger.info { "group: #{name} - applying config maps" }
      group.config_maps.each do |config_map|
        apply_configmap(config_map)
      end
    end
    unless group.before.empty?
      logger.info { "group: #{name} - applying manifests listed in before" }
      group.before.each do |file|
        apply_manifest(file, namespace.name)
      end
    end

    unless group.apps.empty?
      logger.info { "group: #{name} - applying apps" }
      group.apps.each do |app|
        ns = Namespace.new(app.namespace, group.project)
        create_ns(ns)
        apply_app(app)
      end
    end

    unless group.after.empty?
      logger.info { "group: #{name} - applying manifests listed in after" }
      group.after.each do |file|
        apply_manifest(file, namespace.name)
      end
    end
  end
end
