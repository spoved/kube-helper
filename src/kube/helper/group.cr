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

    group.config_maps.each do |s|
      s.namespace = group.namespace.name if s.namespace.nil?
    end

    group.secrets.each do |s|
      s.namespace = group.namespace.name if s.namespace.nil?
    end

    ks = Kube::Helper::Kustomize.build_kustomization(nil, group.name)
    Kube::Helper::Kustomize.with_kustomize(ks) do |ks_path|
      unless group.secrets.empty?
        logger.info { "group: #{name} - applying secrets" }
        group.secrets.each do |secret|
          apply_secret(secret, ks_path)
        end
      end

      unless group.config_maps.empty?
        logger.info { "group: #{name} - applying config maps" }
        group.config_maps.each do |config_map|
          apply_configmap(config_map, ks_path)
        end
      end

      unless group.before.empty?
        logger.info { "group: #{name} - applying manifests listed in before" }
        group.before.each do |file|
          apply_manifest(file, namespace.name, ks_path)
        end
      end

      unless group.apps.empty?
        logger.info { "group: #{name} - applying apps" }
        group.apps.each do |app|
          apply_app(app, name)
        end
      end

      unless group.after.empty?
        logger.info { "group: #{name} - applying manifests listed in after" }
        group.after.each do |file|
          apply_manifest(file, namespace.name, ks_path)
        end
      end
    end
  end
end
