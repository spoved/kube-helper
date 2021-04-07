module Kube::Helper::Group
  def is_helm_app?(options : AppOptions) : Bool
    !(options.chart.nil? && options.chart_url.nil? && options.chart_path.nil?)
  end

  def apply_group(name : String, group : ::Group)
    if group.ignore
      logger.warn { "ignoring group: #{name}" }
      return
    end
    namespace = Namespace.new(name, group.project)

    logger.info { "group: #{name} - checking namespace" }
    create_ns(namespace)

    logger.info { "group: #{name} - applying secrets" }
    group.secrets.each do |secret|
      apply_secret(secret)
    end

    logger.info { "group: #{name} - applying config maps" }
    group.config_maps.each do |config_map|
      apply_configmap(config_map)
    end

    logger.info { "group: #{name} - applying manifests listed in before" }
    group.before.each do |file|
      apply_manifest(file, namespace.name)
    end

    logger.info { "group: #{name} - applying apps" }
    group.apps.each do |app|
      ns = Namespace.new(app.namespace, group.project)
      create_ns(ns)
      apply_app(app)
    end

    logger.info { "group: #{name} - applying manifests listed in after" }
    group.after.each do |file|
      apply_manifest(file, namespace.name)
    end
  end
end
