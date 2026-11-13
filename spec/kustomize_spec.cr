require "./spec_helper"

describe Kube::Helper::Kustomize do
  it "generates stable app provenance independent of the binary version" do
    annotations = YAML.parse(Kube::Helper::Kustomize.build_kustomization("definitions", "foundation").to_yaml)["commonAnnotations"]
    annotations.as_h.keys.map(&.as_s).sort.should eq(%w(kube-helper.alpha.kubernetes.io/group kube-helper.alpha.kubernetes.io/name))
    annotations["kube-helper.alpha.kubernetes.io/group"].as_s.should eq("foundation")
    annotations["kube-helper.alpha.kubernetes.io/name"].as_s.should eq("definitions")
  end

  it "preserves explicit annotations and omits absent app provenance for group wrappers" do
    annotations = YAML.parse(Kube::Helper::Kustomize.build_kustomization(nil, "foundation", {"example.com/owner" => "platform"}).to_yaml)["commonAnnotations"]
    annotations.as_h.keys.map(&.as_s).sort.should eq(%w(example.com/owner kube-helper.alpha.kubernetes.io/group))
    annotations["example.com/owner"].as_s.should eq("platform")
    annotations["kube-helper.alpha.kubernetes.io/group"].as_s.should eq("foundation")
  end
end
