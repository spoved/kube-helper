module Kube::Helper::Kubectl
  abstract def opt(key : Symbol) : Bool | String | Nil | Array(String)

  private setter kubecmd : String? = nil

  private def kubecmd
    @kubecmd ||= "#{opt(:kube_bin)} --kubeconfig #{opt(:kube_config)}"
  end

  def kubectl(args : Array(String), silent = false)
    cmd = "#{self.kubecmd} #{args.join(" ")}"

    if silent
      system_cmd cmd
    else
      run_cmd(cmd)
    end
  end

  def kubectl(*args)
    run_cmd("#{self.kubecmd} #{args.join(" ")}")
  end

  def kubectl?(*args)
    system_cmd?("#{self.kubecmd} #{args.join(" ")}")
  end

  def apply_file(file)
    path = File.exists?(file) ? file : get_path(file)

    if File.exists?(path)
      logger.debug { "applying #{file}" }
      kubectl "apply", apply_server_side(path), "-f", path
    else
      logger.error { "cannot find #{file}" }
    end
  end

  private def apply_server_side(path)
    server_side = File.size(path) > 262144
    "--server-side=#{server_side.to_s}"
  end

  def apply_manifest(path : String, namespace : String)
    return apply_manifest(path) if /^http/ === path

    server_side = File.size(path) > 262144

    if opt(:delete)
      logger.warn { "deleting #{path}" }
      kubectl "delete", "-n", namespace, "-f", path
    else
      logger.debug { "applying #{path}" }
      kubectl "apply", "-n", namespace, apply_server_side(path), "-f", path
    end
  end

  def apply_manifest(path : String)
    if /^http/ === path
      logger.debug { "applying #{path}" }
      kubectl "apply", "-f", path
    else
      apply_file(path)
    end
  end

  def create_ns(ns : Namespace)
    create_ns(ns.name)
    unless ns.project.nil?
      # Rancher project id
      kubectl("annotate", "--overwrite", "namespace",
        ns.name, "field.cattle.io/projectId=local:#{ns.project.not_nil!}")
      kubectl("label", "--overwrite", "namespace",
        ns.name, "field.cattle.io/projectId=#{ns.project.not_nil!}")
    end
    # istio-injection: enabled
    # kubectl label --overwrite pods foo status=unhealthy
    kubectl("label", "--overwrite", "namespace",
      ns.name, "istio-injection=enabled") if ns.istio
  end

  def create_ns(ns)
    unless kubectl?("get", "namespace", ns)
      logger.info { "creating namespace: #{ns}" }
      kubectl("create", "namespace", ns)
    end
  end
end
