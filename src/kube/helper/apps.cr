module Kube::Helper::Apps
  def should_skip?(options : AppOptions) : Bool
    if options.ignore
      true
    elsif (opt(:name_filter) && !opt(:names).as(Array(String)).includes?(options.name))
      true
    else
      false
    end
  end

  def should_skip?(options : KustomizeConfig) : Bool
    if (opt(:name_filter) && !opt(:names).as(Array(String)).includes?(options.name))
      true
    else
      false
    end
  end

  def apply_before(options, ks_path : String)
    options.before.each do |file|
      apply_manifest(file, options.namespace!, ks_path)
    end
  end

  private def _apply_manifests(options, ks_path : String)
    options.manifests.each do |file|
      apply_manifest(file, options.namespace!, ks_path)
    end
  end

  def apply_after(options, ks_path : String)
    options.after.each do |file|
      apply_manifest(file, options.namespace!, ks_path)
    end

    options.config_maps.each do |s|
      apply_configmap s, ks_path
    end

    options.secrets.each do |s|
      apply_secret s, ks_path
    end
  end

  def apply_app(app : AppOptions, group_name : String = "root")
    if should_skip?(app)
      logger.warn { "ignoring app: #{app.name}" }
      return
    end

    app.config_maps.each do |s|
      s.namespace = app.namespace! if s.namespace.nil?
    end

    app.secrets.each do |s|
      s.namespace = app.namespace! if s.namespace.nil?
    end

    ks = Kube::Helper::Kustomize.build_kustomization(app.name, group_name)
    Kube::Helper::Kustomize.with_kustomize(ks) do |ks_path|
      create_ns(app.namespace!)
      apply_before(app, ks_path: ks_path)

      if is_helm_app?(app)
        _run_helm(name: app.name, options: app, ks_path: ks_path)
      end

      apply_kustomize(KustomizeConfig.new(
        app.name, app.namespace, app.kustomize.not_nil!
      ), ks_path) if app.kustomize
      _apply_manifests(app, ks_path: ks_path)

      apply_after(app, ks_path: ks_path)
    end
  end

  def apply_kustomize(k : KustomizeConfig, ks_path)
    path = File.expand_path(k.path)
    tempfile = File.tempfile(prefix: "kustomize", suffix: nil)
    begin
      system_cmd("kustomize build #{path} > #{tempfile.path}")
      apply_file(tempfile.path, ks_path)
    ensure
      tempfile.delete
    end
  end
end
