require "./spec_helper"

class ReadinessFixture < Kube::Helper
  getter calls = [] of Tuple(String, Array(String))
  property fail_apply = false
  property fail_build = false
  property dry_run = false
  property manifest = <<-YAML
  apiVersion: apiextensions.k8s.io/v1
  kind: CustomResourceDefinition
  metadata: {name: widgets.example.com}
  ---
  apiVersion: v1
  kind: ConfigMap
  metadata: {name: ordinary-config}
  ---
  apiVersion: apiextensions.k8s.io/v1
  kind: CustomResourceDefinition
  metadata: {name: agents.example.com}
  YAML

  def initialize(@directory : String)
    @config = Config.from_yaml("context: null\n")
  end

  def opt(key : Symbol) : Bool | String | Nil | Array(String)
    return dry_run if key == :dry_run
    return true if key == :server_side
    return "fixture" if key.in?({:kube_config, :kube_bin, :helm_bin})
    OPTIONS[key]?
  end

  def workdir : String
    @directory
  end

  def kube_context : String?
    nil
  end

  def run_cmd(command, args)
    calls << {command, args.dup}
    if command == "kustomize"
      raise "fixture build failed" if fail_build
      File.write(args.last, manifest)
    end
    raise "fixture apply failed" if fail_apply && args.includes?("apply")
    {output: "", error: "", status: true}
  end
end

private def with_readiness_fixture(&)
  directory = File.tempname("kube-helper-readiness")
  Dir.mkdir(directory)
  begin
    yield ReadinessFixture.new(directory), directory
  ensure
    FileUtils.rm_rf(directory)
  end
end

describe "Declarative native readiness capability" do
  it "passes native Helm readiness and preserves default behavior without opt-in" do
    with_readiness_fixture do |tool, _|
      app = AppOptions.from_yaml("name: controller\nnamespace: controllers\nchart: fixture-chart\nwait: true\natomic: true\ntimeout: 10m\n")
      tool._run_helm("controller", app)
      args = tool.calls.last[1]
      args.should contain("--wait")
      args.should contain("--atomic")
      args[args.index("--timeout").not_nil! + 1].should eq("10m")
      plain = AppOptions.from_yaml("name: plain\nnamespace: default\nchart: fixture-chart\n")
      tool._run_helm("plain", plain)
      tool.calls.last[1].should_not contain("--wait")
      tool.calls.last[1].should_not contain("--atomic")
      tool.calls.last[1].should_not contain("--timeout")
    end
  end

  it "waits only for desired CRDs after successful nonforcing SSA" do
    with_readiness_fixture do |tool, _|
      app = AppOptions.from_yaml("name: definitions\nkustomize: ./crds\nwait_for_crds: true\ntimeout: 90s\n")
      tool.apply_kustomize(app, "foundation")
      apply = tool.calls.find { |_, args| args.includes?("apply") }.not_nil!
      apply[1].should contain("--server-side=true")
      apply[1].should contain("--force-conflicts=false")
      waits = tool.calls.select { |_, args| args.includes?("wait") }
      waits.map { |_, args| args[args.index("--for=condition=Established").not_nil! + 1] }.should eq(%w(customresourcedefinition/agents.example.com customresourcedefinition/widgets.example.com))
      waits.each { |_, args| args.should contain("--timeout=90s") }
      tool.calls.index(apply).not_nil!.should be < tool.calls.index(waits.first).not_nil!
      tool.calls.any? { |_, args| args.includes?("get") || args.includes?("patch") }.should be_false
    end
  end

  it "does no readiness observation during dry-run" do
    with_readiness_fixture do |tool, _|
      tool.dry_run = true
      tool.apply_kustomize(AppOptions.from_yaml("name: definitions\nkustomize: ./crds\nwait_for_crds: true\n"), "foundation")
      tool.calls.any? { |_, args| args.includes?("wait") }.should be_false
      tool.calls.find { |_, args| args.includes?("apply") }.not_nil![1].should contain("--dry-run=client")
    end
  end

  it "propagates build/apply failures without waiting or continuing" do
    with_readiness_fixture do |tool, _|
      app = AppOptions.from_yaml("name: definitions\nkustomize: ./crds\nwait_for_crds: true\n")
      tool.fail_build = true
      expect_raises(Exception, /fixture build failed/) { tool.apply_kustomize(app, "foundation") }
      tool.calls.any? { |_, args| args.includes?("apply") || args.includes?("wait") }.should be_false
      tool.fail_build = false
      tool.fail_apply = true
      expect_raises(Exception, /fixture apply failed/) { tool.apply_kustomize(app, "foundation") }
      tool.calls.any? { |_, args| args.includes?("wait") }.should be_false
    end
  end

  it "rejects invalid readiness durations and empty CRD selections before writes" do
    %w(0s -1s forever 1s--wait).each do |timeout|
      app = AppOptions.from_yaml("name: definitions\ntimeout: #{timeout}\n")
      expect_raises(Exception, /positive native duration/) { app.readiness_timeout }
    end
    with_readiness_fixture do |tool, _|
      tool.manifest = "apiVersion: v1\nkind: Namespace\nmetadata: {name: fixture}\n"
      app = AppOptions.from_yaml("name: definitions\nkustomize: ./crds\nwait_for_crds: true\n")
      expect_raises(Exception, /at least one desired CRD/) { tool.apply_kustomize(app, "foundation") }
      tool.calls.any? { |_, args| args.includes?("apply") }.should be_false
    end
  end
end
