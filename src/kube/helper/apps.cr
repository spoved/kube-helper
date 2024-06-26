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
    logger.info { "applying app #{group_name}/#{app.name}" }
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

    ks = Kube::Helper::Kustomize.build_kustomization(app.name, group_name, config.annotations)

    Kube::Helper::Kustomize.with_kustomize(ks) do |ks_path|
      run_before(app)
      apply_before(app, ks_path: ks_path)
    end

    # If this is a helm app
    if is_helm_app?(app)
      Kube::Helper::Kustomize.with_kustomize(ks, app.kustomize) do |ks_path|
        _run_helm(name: app.name, options: app, ks_path: ks_path)
      end
    else
      # Run any commands
      app.run.each do |cmd|
        run_cmd(*parse_cmd(cmd))
      end

      # Apply kustomize
      apply_kustomize(app, group_name) if app.kustomize
    end

    Kube::Helper::Kustomize.with_kustomize(ks) do |ks_path|
      _apply_manifests(app, ks_path: ks_path)
      apply_after(app, ks_path: ks_path)
      run_after(app)
    end
  end

  # This method applies a Kustomize configuration to a given path.
  # It takes a KustomizeConfig object and the ks_path to apply the configuration to.
  def apply_kustomize(k : KustomizeConfig, ks_path)
    # Get the path of the Kustomize configuration and create a temporary file to store the output.
    path = File.expand_path(k.path)
    tempfile = File.tempfile(prefix: "kustomize", suffix: nil)

    begin
      # Use the system command to build the Kustomize configuration and output the results to the temporary file.
      system_cmd("kustomize build #{path} -o #{tempfile.path}")

      # Apply the configuration from the temporary file to the given path.
      apply_file(tempfile.path, ks_path)
    ensure
      # Delete the temporary file.
      tempfile.delete
    end
  end

  # This method applies the Kustomize configuration for the given application and group.
  # It builds the Kustomize configuration for the application using the group name, then applies it.
  def apply_kustomize(app : AppOptions, group_name)
    # Build the Kustomize configuration for the application using the group name.
    ks = Kube::Helper::Kustomize.build_kustomization(app.name, group_name, config.annotations)

    # Apply the Kustomize configuration.
    Kube::Helper::Kustomize.with_kustomize(ks) do |ks_path|
      k = KustomizeConfig.new(
        app.name, app.namespace, app.kustomize.not_nil!
      )
      apply_kustomize(k, ks_path)
    end
  end

  # This method runs the 'run_before' commands specified in the application's configuration.
  def run_before(app)
    app.run_before.each do |cmd|
      run_cmd(*parse_cmd(cmd))
    end
  end

  # This method runs the 'run_after' commands specified in the application's configuration.
  def run_after(app)
    app.run_after.each do |cmd|
      run_cmd(*parse_cmd(cmd))
    end
  end
end
