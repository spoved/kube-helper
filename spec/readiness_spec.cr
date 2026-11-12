require "./spec_helper"

class ReadinessFixture < Kube::Helper
  getter calls = [] of Tuple(String, Array(String))
  property fail_apply = false
  property fail_build = false
  property fail_rollout = false
  property deleting = false
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
    return deleting if key == :delete
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
    raise "fixture rollout timed out" if fail_rollout && args.includes?("rollout")
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

  it "continues an explicitly selected field manager without forcing conflicts" do
    with_readiness_fixture do |tool, _|
      app = AppOptions.from_yaml("name: definitions\nkustomize: ./crds\nwait_for_crds: true\nfield_manager: quantum-operator-crd\n")
      tool.apply_kustomize(app, "foundation")
      apply = tool.calls.find { |_, args| args.includes?("apply") }.not_nil!
      apply[1].should contain("--field-manager=quantum-operator-crd")
      apply[1].should contain("--force-conflicts=false")
    end
  end

  it "rejects an invalid field manager before apply" do
    with_readiness_fixture do |tool, _|
      app = AppOptions.from_yaml("name: definitions\nkustomize: ./crds\nfield_manager: \"bad\\tmanager\"\n")
      expect_raises(Exception, /field_manager requires/) { tool.apply_app(app, "foundation") }
      tool.calls.any? { |_, args| args.includes?("apply") }.should be_false
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

private def rollout_manifest : String
  <<-YAML
  apiVersion: apps/v1
  kind: Deployment
  metadata: {name: controller, namespace: controllers}
  ---
  apiVersion: apps/v1
  kind: DaemonSet
  metadata: {name: agent, namespace: agents}
  ---
  apiVersion: apps/v1
  kind: StatefulSet
  metadata: {name: data, namespace: storage}
  ---
  apiVersion: apps/v1
  kind: Deployment
  metadata: {name: context-default}
  ---
  apiVersion: v1
  kind: Service
  metadata: {name: controller, namespace: controllers}
  ---
  apiVersion: batch/v1
  kind: Job
  metadata: {name: bootstrap, namespace: controllers}
  ---
  apiVersion: product.example/v1
  kind: Tenant
  metadata: {name: product}
  YAML
end

describe "Opt-in Kustomize native rollout readiness" do
  it "waits for desired native kinds and exact namespaces before subsequent actions/apps" do
    with_readiness_fixture do |tool, _|
      tool.manifest = rollout_manifest
      group = Group.from_yaml("name: foundation\napps:\n  - name: controller\n    namespace: wrong-app-fallback\n    kustomize: ./controller\n    wait: true\n    timeout: 7m\n    run_after: [after-ready]\n  - name: later\n    run: [next-app]\n")
      tool.apply_group(group)
      apply = tool.calls.index { |_, args| args.includes?("apply") }.not_nil!
      rollouts = tool.calls.select { |_, args| args.includes?("rollout") }
      rollouts.map { |_, args| args[args.index("status").not_nil! + 1] }.should eq(%w(deployment/controller daemonset/agent statefulset/data deployment/context-default))
      rollouts.first(3).map { |_, args| args[args.index("--namespace").not_nil! + 1] }.should eq(%w(controllers agents storage))
      rollouts.last[1].should_not contain("--namespace")
      rollouts.last[1].should_not contain("wrong-app-fallback")
      rollouts.each do |call|
        call[1].should contain("--timeout=7m")
        tool.calls.index(call).not_nil!.should be > apply
      end
      after_ready = tool.calls.index { |command, _| command == "after-ready" }.not_nil!
      after_ready.should be > tool.calls.index(rollouts.last).not_nil!
      tool.calls.index { |command, _| command == "next-app" }.not_nil!.should be > after_ready
      tool.calls.any? { |_, args| args.includes?("get") || args.includes?("patch") }.should be_false
    end
  end

  it "propagates a rollout timeout without starting later actions/apps" do
    with_readiness_fixture do |tool, _|
      tool.manifest = rollout_manifest
      tool.fail_rollout = true
      group = Group.from_yaml("name: foundation\napps:\n  - name: controller\n    kustomize: ./controller\n    wait: true\n    timeout: 1s\n    run_after: [after-ready]\n  - name: later\n    run: [next-app]\n")
      expect_raises(Exception, /fixture rollout timed out/) { tool.apply_group(group) }
      tool.calls.count { |_, args| args.includes?("rollout") }.should eq(1)
      tool.calls.any? { |command, _| command.in?({"after-ready", "next-app"}) }.should be_false
    end
  end

  it "validates all rollout targets before apply and never waits after an apply failure" do
    with_readiness_fixture do |tool, _|
      app = AppOptions.from_yaml("name: controller\nkustomize: ./controller\nwait: true\n")
      tool.manifest = rollout_manifest.sub("name: data, namespace: storage", "name: data, namespace: bad/namespace")
      expect_raises(Exception, /invalid desired rollout namespace/) { tool.apply_kustomize(app, "foundation") }
      tool.calls.any? { |_, args| args.includes?("apply") || args.includes?("rollout") }.should be_false
      tool.manifest = rollout_manifest
      tool.fail_apply = true
      expect_raises(Exception, /fixture apply failed/) { tool.apply_kustomize(app, "foundation") }
      tool.calls.any? { |_, args| args.includes?("rollout") }.should be_false
    end
  end

  it "keeps unselected, dry-run and delete operations free of rollout observations" do
    with_readiness_fixture do |tool, _|
      tool.manifest = rollout_manifest
      tool.apply_kustomize(AppOptions.from_yaml("name: plain\nkustomize: ./controller\n"), "foundation")
      app = AppOptions.from_yaml("name: controller\nkustomize: ./controller\nwait: true\n")
      tool.dry_run = true
      tool.apply_kustomize(app, "foundation")
      tool.dry_run = false
      tool.deleting = true
      tool.apply_kustomize(app, "foundation")
      tool.calls.any? { |_, args| args.includes?("rollout") }.should be_false
    end
  end
end
