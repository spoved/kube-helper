require "file_utils"
require "spoved/logger"

module Kube::Helper::Kustomize
  spoved_logger

  HEADER = {
    "apiVersion" => "kustomize.config.k8s.io/v1beta1",
    "kind"       => "Kustomization",
    "resources"  => ["all.yaml"],
  }

  def self.build_kustomization(name, group, extra = nil)
    common = {
      "kube-helper.alpha.kubernetes.io/version" => Kube::Helper::VERSION,
      "kube-helper.alpha.kubernetes.io/group"   => group,
      "kube-helper.alpha.kubernetes.io/name"    => name,
    }

    unless extra.nil?
      common.merge!(extra)
    end

    HEADER.dup.merge({
      "commonAnnotations" => common.reject { |_, v| v.nil? },
    })
  end

  def self.with_kustomize(kustomize, *paths)
    config = kustomize.dup
    temp_dir = File.tempname(prefix: "kube-helper-kustomize", suffix: nil)

    wrapper = <<-EOF
    #!/bin/bash
    cat <&0 > #{temp_dir}/all.yaml
    kustomize build #{temp_dir} && rm #{temp_dir}/all.yaml
    EOF

    begin
      Kube::Helper.logger.trace { "Creating temporary directory #{temp_dir}" }
      FileUtils.mkdir_p(temp_dir)

      paths.each do |path|
        if path && Dir.exists?(path)
          dir_name = File.basename(path)
          FileUtils.cp_r(path, temp_dir)
          raise "Cannot copy #{path} to #{temp_dir}" unless Dir.exists?(File.join(temp_dir, dir_name))
          config["resources"].as(Array(String)) << dir_name
        end
      end

      File.join(temp_dir, "kustomize").tap do |path|
        File.write(path, wrapper)
        File.chmod(path, File::Permissions::OwnerAll)
      end

      temp_dir.tap do |path|
        File.write(File.join(path, "kustomization.yaml"), config.to_yaml)
      end

      yield temp_dir
    ensure
      FileUtils.rm_r(temp_dir) if Dir.exists?(temp_dir)
    end
  end
end
