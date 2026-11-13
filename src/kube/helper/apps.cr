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
    app.readiness_timeout if app.timeout || app.wait_for_crds || app.wait
    app.validated_field_manager
    validate_prune!(app.prune.not_nil!) if app.prune
    raise "prune requires a Kustomize-only application" if app.prune && (!app.kustomize || is_helm_app?(app))
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
  def apply_kustomize(k : KustomizeConfig, ks_path, wait_for_crds = false, timeout = "180s", wait_for_rollout = false, field_manager = nil, force_conflicts = false, prune : PruneOptions? = nil, group_name = "root")
    # Get the path of the Kustomize configuration and create a temporary file to store the output.
    path = File.expand_path(k.path)
    tempfile = File.tempfile(prefix: "kustomize", suffix: nil)

    begin
      # Use the system command to build the Kustomize configuration and output the results to the temporary file.
      run_cmd("kustomize", ["build", path, "-o", tempfile.path])
      manifest = File.read(tempfile.path)
      crds = wait_for_crds ? desired_crd_names(manifest) : [] of String
      rollouts = wait_for_rollout ? desired_rollout_targets(manifest) : [] of Tuple(String, String, String?)
      raise "wait_for_crds requires at least one desired CRD" if wait_for_crds && crds.empty?

      # Apply the configuration from the temporary file to the given path.
      if prune
        apply_pruned_kustomize(manifest, tempfile.path, ks_path, k.name, group_name, prune, field_manager, force_conflicts)
      else
        apply_file(tempfile.path, ks_path, field_manager, force_conflicts)
      end
      if wait_for_crds && !dry_run? && opt(:delete) != true
        crds.each do |name|
          kubectl(["wait", "--for=condition=Established", "customresourcedefinition/" + name, "--timeout=" + timeout])
        end
      end
      if wait_for_rollout && !dry_run? && opt(:delete) != true
        rollouts.each do |kind, name, namespace|
          args = ["rollout", "status", kind + "/" + name, "--timeout=" + timeout]
          args += ["--namespace", namespace] if namespace
          kubectl(args)
        end
      end
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
      apply_kustomize(k, ks_path, app.wait_for_crds, app.readiness_timeout, app.wait, app.validated_field_manager, app.force_conflicts, app.prune, group_name)
    end
  end

  # Only native workload rollouts, selected from the same desired bytes applied
  # below. Missing namespace deliberately keeps kubectl's apply-context default.
  private def desired_rollout_targets(manifest : String) : Array(Tuple(String, String, String?))
    YAML.parse_all(manifest).compact_map do |object|
      next if object.raw.nil?
      kind = object["kind"]?.try(&.as_s?)
      next unless kind == "Deployment" || kind == "DaemonSet" || kind == "StatefulSet"
      raise "native rollout wait requires apps/v1 workloads" unless object["apiVersion"].as_s == "apps/v1"
      name = object["metadata"]["name"].as_s
      raise "invalid desired rollout name" unless name.bytesize <= 253 && name.matches?(/\A[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\z/)
      namespace = nil.as(String?)
      if declared = object["metadata"]["namespace"]?
        namespace = declared.as_s? || raise "invalid desired rollout namespace"
        raise "invalid desired rollout namespace" unless namespace.matches?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/)
      end
      {kind.not_nil!.downcase, name, namespace}
    end.uniq
  end

  private def desired_crd_names(manifest : String) : Array(String)
    YAML.parse_all(manifest).compact_map do |object|
      next if object.raw.nil? || object["kind"]?.try(&.as_s) != "CustomResourceDefinition"
      raise "CRD establishment requires apiextensions.k8s.io/v1" unless object["apiVersion"].as_s == "apiextensions.k8s.io/v1"
      name = object["metadata"]["name"].as_s
      raise "invalid desired CRD name" unless name.matches?(/\A[a-z0-9][a-z0-9.-]*[a-z0-9]\z/)
      name
    end.uniq.sort
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
