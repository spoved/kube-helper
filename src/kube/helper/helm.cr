module Kube::Helper::Helm
  HELMCMD = "helm --kubeconfig #{KUBECONFIG}"

  # Run a helm command
  def helm(*args, namespace, silent = false, json = true)
    cmd = "#{HELMCMD} --namespace #{namespace} "
    cmd += " -o json " if json
    cmd += args.join(" ")

    if silent
      system_cmd cmd
    else
      run_cmd(cmd)
    end
  end

  # Will update all helm repos
  def update_helm_repos
    logger.info { "updating helm repos" }

    # Gather current repos
    curr_repos = JSON.parse(`helm repo list -o json`)
    names = Array(String).new
    curr_repos.as_a.each do |repo|
      names << repo["name"].as_s
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
      yield File.join(WORKDIR, options.chart_path.not_nil!)
    else
      raise "No chart specified"
    end
  end

  # Build the helm values file and provide the path. If a file path is defined, will yield that back.
  def _helm_with_values(options)
    if !options.values.nil? && options.values.not_nil!.raw.is_a?(String)
      path = File.join(WORKDIR, options.values.not_nil!.as_s)
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

  def _run_helm(mode, name, options)
    logger.info { "#{mode} helm app: #{name}" }

    _helm_with_chart(options) do |chart|
      unless options.values.nil?
        _helm_with_values(options) do |values_path|
          create_ns(options.namespace)
          helm(mode, options.name, chart, "-f", values_path, namespace: options.namespace, json: false)
        end
      else
        helm(mode, options.name, chart, namespace: options.namespace, json: false)
      end
    end
  end
end
