module Kube::Helper::Kustomize
  HEADER = {
    "apiVersion" => "kustomize.config.k8s.io/v1beta1",
    "kind"       => "Kustomization",
    "resources"  => ["all.yaml"],
  }

  def self.build_kustomization(group, name)
    HEADER.dup.merge({
      "commonAnnotations" => {
        "kube-helper.alpha.kubernetes.io/version" => Kube::Helper::VERSION,
        "kube-helper.alpha.kubernetes.io/group"   => group,
        "kube-helper.alpha.kubernetes.io/name"    => name,
      }.reject { |_, v| v.nil? },
    })
  end

  def self.with_kustomize(kustomize)
    temp_dir = File.tempname(prefix: "kube-helper-kustomize", suffix: nil)

    wrapper = <<-EOF
    #!/bin/bash
    cat <&0 > #{temp_dir}/all.yaml
    kustomize build #{temp_dir} && rm #{temp_dir}/all.yaml
    EOF

    begin
      FileUtils.mkdir_p(temp_dir)

      File.join(temp_dir, "kustomize").tap do |path|
        File.write(path, wrapper)
        File.chmod(path, File::Permissions::OwnerAll)
      end

      temp_dir.tap do |path|
        File.write(File.join(path, "kustomization.yaml"), kustomize.to_yaml)
      end

      yield temp_dir
    ensure
      FileUtils.rm_r(temp_dir) if Dir.exists?(temp_dir)
    end
  end
end
