module Kube::Helper::Helm
  abstract def opt(key : Symbol) : Bool | String | Nil | Array(String)
  abstract def workdir : String
  abstract def kube_context : String?

  private setter helmcmd : String? = nil

  private def helmcmd
    @helmcmd ||= "#{opt(:helm_bin)} --kubeconfig #{opt(:kube_config)}" + (kube_context ? " --kube-context #{kube_context}" : "")
  end

  # Run a helm command
  def helm(*args, namespace, silent = false, json = true, version : String? = nil, ks_path : String? = nil)
    cmd = "#{self.helmcmd} --namespace #{namespace} "
    cmd += " -o json " if json
    cmd += " --version #{version} " unless version.nil?

    cmd += args.join(" ")

    if ks_path
      cmd += " --post-renderer #{File.join(ks_path, "kustomize")}"
    end

    if silent
      system_cmd cmd
    else
      run_cmd(cmd)
    end
  end

  # Will update all helm repos
  def update_helm_repos
    logger.info { "updating helm repos" }
    names = Array(String).new

    begin
      # Gather current repos
      curr_repos = JSON.parse(`helm repo list -o json`)
      curr_repos.as_a.each do |repo|
        names << repo["name"].as_s
      end
    rescue ex : JSON::ParseException
      logger.warn { "unable to check current helm repos" }
    end

    config.helm.repos.each do |k, v|
      # If its missing add it
      unless names.includes?(k)
        cmd = "helm repo add #{k} #{v}"
        run_cmd(cmd)
      end
    end

    run_cmd("helm repo update")
  end

  # check to see if a helm chart is installed
  def chart_installed?(name, options)
    resp = helm("list", namespace: options.namespace, silent: true)
    installed = JSON.parse resp[:output]
    found = false
    installed.as_a.each do |release|
      if release["name"]? && release["name"].as_s == name
        found = true
        break
      end
    end
    found
  end

  # Will yield the path to the helm chart.
  def _helm_with_chart(options)
    if !options.chart.nil?
      yield options.chart.not_nil!
    elsif !options.chart_url.nil?
      begin
        tempfile = File.tempfile
        system_cmd("wget \"#{options.chart_url.not_nil!}\" -O #{tempfile.path}")
        yield tempfile.path
      rescue ex
        raise ex
      ensure
        tempfile.delete unless tempfile.nil?
      end
    elsif !options.chart_path.nil?
      yield File.join(self.workdir, options.chart_path.not_nil!)
    else
      raise "No chart specified"
    end
  end

  # Build the helm values file and provide the path. If a file path is defined, will yield that back.
  def _helm_with_values(options)
    if !options.values.nil? && options.values.not_nil!.raw.is_a?(String)
      path = File.join(self.workdir, options.values.not_nil!.as_s)
      raise "Unable to find values file #{options.values}" unless File.exists?(path)
      yield path
    else
      begin
        tempfile = File.tempfile(".yml") do |file|
          file.print(options.values.to_yaml)
        end
        yield tempfile.path
      rescue ex
        raise ex
      ensure
        tempfile.delete unless tempfile.nil?
      end
    end
  end

  def _run_helm(name, options : AppOptions, ks_path : String? = nil)
    logger.info { "helm app: #{name}" }

    _helm_with_chart(options) do |chart|
      if options.values.nil?
        helm(
          "upgrade", "--install", options.name, chart, "--create-namespace",
          namespace: options.namespace,
          json: false,
          version: options.version,
          ks_path: ks_path,
        )
      else
        _helm_with_values(options) do |values_path|
          helm(
            "upgrade", "--install", options.name, chart, "--create-namespace",
            "-f", values_path,
            namespace: options.namespace,
            json: false,
            version: options.version,
            ks_path: ks_path,
          )
        end
      end
    end
  end
end
