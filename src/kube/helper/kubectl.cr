require "http/client"
require "halite"

module Kube::Helper::Kubectl
  abstract def opt(key : Symbol) : Bool | String | Nil | Array(String)
  abstract def kube_context : String?

  private setter kube_args : Array(String)? = nil

  private def kubecmd : String
    opt(:kube_bin).as(String)
  end

  private def kube_args
    @kube_args ||= (kube_context ? ["--kubeconfig", opt(:kube_config).as(String), "--context", kube_context.not_nil!] : ["--kubeconfig", opt(:kube_config).as(String)])
  end

  def kubectl(args : Array(String), silent = false)
    if args.includes?("apply") || args.includes?("delete")
      args = (args.dup << "--dry-run=client") if dry_run?
    end

    if silent
      system_cmd(kubecmd, (kube_args + args))
    else
      run_cmd(kubecmd, (kube_args + args))
    end
  end

  def kubectl(*args)
    kubectl(kube_args + args.to_a)
  end

  def kubectl?(*args)
    system_cmd?(self.kubecmd, (kube_args + args.to_a))
  end

  def apply_file(file, ks_path : String)
    path = File.exists?(file) ? file : get_path(file)

    if File.exists?(path)
      logger.debug { "applying #{file}" }
      FileUtils.cp(path, File.join(ks_path, "all.yaml"))
      kubectl "apply", apply_server_side(path), apply_force_conflicts, "-k", ks_path
    else
      logger.error { "cannot find #{file}" }
    end
  end

  private def apply_force_conflicts
    if opt(:force_conflicts) && opt(:server_side)
      return "--force-conflicts=true"
    end
    "--force-conflicts=false"
  end

  private def apply_server_side(path)
    if opt(:server_side) && opt(:force_conflicts)
      return "--server-side=true"
    end

    return "--server-side=false"
    server_side = File.size(path) > 262144
    "--server-side=#{server_side}"
  end

  def apply_manifest(path : String, namespace : String, ks_path : String)
    return apply_manifest(path, ks_path) if /^http/ === path
    create_ns(namespace)
    FileUtils.cp(path, File.join(ks_path, "all.yaml"))
    if opt(:delete)
      logger.warn { "deleting #{path}" }
      kubectl "delete", "-n", namespace, "-k", ks_path
    else
      logger.debug { "applying #{path}" }
      kubectl "apply", "-n", namespace, apply_server_side(path), apply_force_conflicts, "-k", ks_path
    end
  end

  def apply_manifest(path : String, ks_path : String)
    if /^http/ === path
      logger.debug { "applying #{path}" }
      begin
        file = ks_path ? File.open(File.join(ks_path, "all.yaml"), "w") : File.tempfile
        Halite.get(path) do |response|
          if response.success?
            IO.copy(response.body_io, file)
          else
            pp response
            logger.error { "cannot get #{path}" }
            exit 1
          end
        end
      rescue ex
        raise ex
      ensure
        file.try &.close
      end
      kubectl "apply", "-k", ks_path
    else
      apply_file(path, ks_path)
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

  def create_ns(ns : String)
    unless kubectl?("get", "namespace", ns)
      logger.info { "creating namespace: #{ns}" }
      kubectl("create", "namespace", ns)
    end
  end
end
