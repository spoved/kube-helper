module Kube::Helper::Apps
  def should_skip?(options) : Bool
    if options.ignore
      true
    elsif (opt(:name_filter) && !opt(:names).as(Array(String)).includes?(options.name))
      true
    else
      false
    end
  end

  def apply_before(options)
    options.before.each do |file|
      apply_manifest(file, options.namespace)
    end
  end

  private def _apply_manifests(options)
    options.manifests.each do |file|
      apply_manifest(file, options.namespace)
    end
  end

  def apply_after(options)
    options.after.each do |file|
      apply_manifest(file, options.namespace)
    end

    options.config_maps.each do |s|
      apply_configmap s
    end

    options.secrets.each do |s|
      apply_secret s
    end
  end

  def apply_app(app : AppOptions)
    if should_skip?(app)
      logger.warn { "ignoring app: #{app.name}" }
      return
    end

    apply_before(app)

    if is_helm_app?(app)
      if chart_installed?(app.name, app)
        _run_helm("upgrade", app.name, app)
      else
        _run_helm("install", app.name, app)
      end
    end
    _apply_manifests(app)
    apply_after(app)
  end
end
