require "./spec_helper"

class PruningFixture < Kube::Helper
  getter calls = [] of Array(String)
  getter objects = {} of String => JSON::Any
  getter deletions = [] of JSON::Any
  property manifest = ""
  property dry_run = false
  property deleting = false
  property fail_apply = false
  property fail_delete = false
  property fail_save_after_create = false
  property race_create = false
  property race_delete = false
  property finalize_delete = false
  property race_apply = false
  property takeover_apply = false
  @serial = 0

  def initialize(@directory : String)
    @config = Config.from_yaml("context: null\n")
  end

  def opt(key : Symbol) : Bool | String | Nil | Array(String)
    return dry_run if key == :dry_run
    return deleting if key == :delete
    return true if key == :server_side
    return "fixture" if key.in?({:kube_config, :kube_bin})
    OPTIONS[key]?
  end

  def kube_context : String?
    nil
  end

  def workdir : String
    @directory
  end

  def key(object : JSON::Any) : String
    object["apiVersion"].as_s + "/" + object["kind"].as_s + "/" + object["metadata"]["name"].as_s
  end

  def value(args, flag)
    args[args.index(flag).not_nil! + 1]
  end

  def touch(object : JSON::Any, replace_uid = false) : JSON::Any
    @serial += 1
    metadata = object["metadata"].as_h
    metadata["uid"] = JSON::Any.new("uid-#{@serial}") if replace_uid || !metadata.has_key?("uid")
    metadata["resourceVersion"] = JSON::Any.new(@serial.to_s)
    object
  end

  def copy(object : JSON::Any) : JSON::Any
    JSON.parse(object.to_json)
  end

  def seed(name : String, foreign = false) : JSON::Any
    object = JSON.parse({"apiVersion" => "v1", "kind" => "ConfigMap", "metadata" => {"name" => name, "namespace" => "intent", "annotations" => {"kube-helper.alpha.kubernetes.io/group" => "foundation", "kube-helper.alpha.kubernetes.io/name" => foreign ? "foreign" : "desired"}}}.to_json)
    objects[key(object)] = touch(object)
  end

  def inventory : JSON::Any
    JSON.parse(objects["v1/ConfigMap/helper-inventory"]["data"]["inventory.json"].as_s)
  end

  def owner : String
    objects["v1/ConfigMap/helper-inventory"]["metadata"]["uid"].as_s
  end

  def unlock
    objects["v1/ConfigMap/helper-inventory"]["metadata"]["annotations"].as_h.delete(Kube::Helper::Pruning::PRUNE_LOCK)
  end

  def run_cmd(command, args)
    calls << args.dup
    output = ""
    if command == "kustomize"
      File.write(args.last, manifest)
    elsif index = args.index("get")
      name = args[index + 2]
      # All fixtures select only ConfigMaps; production supports the full native
      # allow-list and computes exact fully qualified API resource names.
      output = objects["v1/ConfigMap/#{name}"]?.try(&.to_json) || ""
    elsif args.includes?("patch")
      object = objects["v1/ConfigMap/" + value(args, "configmap")]
      JSON.parse(value(args, "-p")).as_a.each do |operation|
        path = operation["path"].as_s
        target = if path.starts_with?("/metadata/annotations/")
                   object["metadata"]["annotations"].as_h
                 else
                   object["metadata"].as_h
                 end
        field = path.split('/').last.gsub("~1", "/")
        case operation["op"].as_s
        when "test"
          raise "fixture precondition failed" unless target[field]? == operation["value"]
        when "add"
          target[field] = operation["value"]
        when "remove"
          target.delete(field)
        end
      end
      output = touch(object).to_json
    elsif args.includes?("create") || args.includes?("replace")
      object = JSON.parse(File.read(value(args, "-f")))
      identity = key(object)
      if args.includes?("create")
        if race_create && identity != "v1/ConfigMap/helper-inventory"
          self.race_create = false
          seed(object["metadata"]["name"].as_s, foreign: true)
        end
        raise "fixture AlreadyExists" if objects.has_key?(identity)
      else
        raise "fixture interrupted save" if fail_save_after_create && identity == "v1/ConfigMap/helper-inventory" && objects.has_key?("v1/ConfigMap/new")
        previous = objects[identity]
        raise "fixture replace conflict" unless object["metadata"]["uid"] == previous["metadata"]["uid"] && object["metadata"]["resourceVersion"] == previous["metadata"]["resourceVersion"]
      end
      objects[identity] = touch(copy(object))
      output = objects[identity].to_json
    elsif args.includes?("apply")
      raise "fixture apply failed" if fail_apply
      unless args.includes?("--dry-run=client")
        YAML.parse_all(File.read(File.join(value(args, "-k"), "all.yaml"))).each do |document|
          object = JSON.parse(document.to_json)
          identity = key(object)
          if live = objects[identity]?
            touch(live) if race_apply
            raise "fixture apply conflict" if object["metadata"]["uid"]? && (object["metadata"]["uid"] != live["metadata"]["uid"] || object["metadata"]["resourceVersion"] != live["metadata"]["resourceVersion"])
          end
          objects[identity] = touch(copy(object))
        end
      end
      if takeover_apply
        inventory_object = objects["v1/ConfigMap/helper-inventory"]
        inventory_object["metadata"]["annotations"].as_h[Kube::Helper::Pruning::PRUNE_LOCK] = JSON::Any.new({"token" => "successor", "expires" => Time.utc.to_unix + 120}.to_json)
        touch(inventory_object)
      end
    elsif args.includes?("delete")
      raise "fixture deletion failed" if fail_delete
      options = JSON.parse(File.read(value(args, "-f")))
      deletions << options
      name = value(args, "--raw").split('/').last
      identity = "v1/ConfigMap/" + name
      object = objects[identity]
      touch(object, replace_uid: true) if race_delete
      raise "fixture delete precondition failed" unless options["preconditions"]["uid"] == object["metadata"]["uid"] && options["preconditions"]["resourceVersion"] == object["metadata"]["resourceVersion"]
      if finalize_delete
        object["metadata"].as_h["deletionTimestamp"] = JSON::Any.new("2026-11-12T00:00:00Z")
        touch(object)
      else
        objects.delete(identity)
      end
    end
    {output: output, error: "", status: true}
  end
end

private def with_pruning_fixture(&)
  directory = File.tempname("kube-helper-pruning")
  Dir.mkdir(directory)
  begin
    yield PruningFixture.new(directory)
  ensure
    FileUtils.rm_rf(directory)
  end
end

private def prune_app : AppOptions
  AppOptions.from_yaml(<<-YAML)
  name: desired
  kustomize: ./intent
  prune:
    namespace: intent
    inventory: helper-inventory
    kinds: [v1/ConfigMap]
  YAML
end

private def prune_manifest(*names : String) : String
  names.map { |name| "apiVersion: v1\nkind: ConfigMap\nmetadata: {name: #{name}, namespace: intent}\ndata: {value: desired}\n" }.join("---\n")
end

describe "Scoped Kustomize pruning" do
  it "initializes desired legacy objects only and prunes omissions with exact native preconditions after apply" do
    with_pruning_fixture do |tool|
      tool.seed("keep")
      tool.seed("remove")
      tool.seed("historical")
      tool.manifest = prune_manifest("keep", "remove")
      tool.apply_kustomize(prune_app, "foundation")
      tool.inventory["entries"].as_a.map { |entry| entry["name"].as_s }.should eq(%w(keep remove))
      tool.calls.any? { |args| args.includes?("delete") }.should be_false
      prior_uid = tool.objects["v1/ConfigMap/remove"]["metadata"]["uid"].as_s
      tool.calls.clear
      tool.manifest = prune_manifest("keep")
      tool.apply_kustomize(prune_app, "foundation")
      tool.objects.has_key?("v1/ConfigMap/remove").should be_false
      tool.objects.has_key?("v1/ConfigMap/historical").should be_true
      tool.deletions.last["preconditions"]["uid"].as_s.should eq(prior_uid)
      tool.deletions.last["preconditions"]["resourceVersion"].as_s.should_not be_empty
      tool.calls.index { |args| args.includes?("apply") }.not_nil!.should be < tool.calls.index { |args| args.includes?("delete") }.not_nil!
      tool.calls.select { |args| args.includes?("get") }.all? { |args| args.includes?("--namespace") && !args.includes?("--all-namespaces") && !args.includes?("--selector") }.should be_true
      tool.inventory["entries"].as_a.map { |entry| entry["name"].as_s }.should eq(["keep"])
    end
  end

  it "creates absent objects without overwriting a racing foreign object" do
    with_pruning_fixture do |tool|
      tool.manifest = prune_manifest("new")
      tool.race_create = true
      expect_raises(Exception, /AlreadyExists/) { tool.apply_kustomize(prune_app, "foundation") }
      tool.calls.any? { |args| args.includes?("apply") || args.includes?("delete") }.should be_false
      tool.objects["v1/ConfigMap/new"]["metadata"]["annotations"]["kube-helper.alpha.kubernetes.io/name"].as_s.should eq("foreign")
    end
  end

  it "reserves new objects, applies normally, and handles an empty desired set" do
    with_pruning_fixture do |tool|
      tool.manifest = prune_manifest("new")
      tool.apply_kustomize(prune_app, "foundation")
      uid = tool.objects["v1/ConfigMap/new"]["metadata"]["uid"].as_s
      tool.inventory["entries"][0]["uid"].as_s.should eq(uid)
      tool.inventory["entries"][0]["claimed"].as_bool.should be_true
      tool.calls.clear
      tool.manifest = ""
      tool.apply_kustomize(prune_app, "foundation")
      tool.calls.any? { |args| args.includes?("apply") }.should be_false
      tool.objects.has_key?("v1/ConfigMap/new").should be_false
      tool.inventory["entries"].as_a.should be_empty
    end
  end

  it "uses the same scoped manager for reservation create and subsequent apply" do
    with_pruning_fixture do |tool|
      tool.manifest = prune_manifest("new")
      app = prune_app
      app.field_manager = "intent-publisher"
      tool.apply_kustomize(app, "foundation")
      creates = tool.calls.select { |args| args.includes?("create") }
      creates.last.should contain("--field-manager=intent-publisher")
      tool.calls.find { |args| args.includes?("apply") }.not_nil!.should contain("--field-manager=intent-publisher")
    end
    with_pruning_fixture do |tool|
      tool.manifest = prune_manifest("new")
      tool.apply_kustomize(prune_app, "foundation")
      tool.calls.select { |args| args.includes?("create") }.last.should contain("--field-manager=kubectl")
    end
  end

  it "never deletes when apply fails and retries the durable union" do
    with_pruning_fixture do |tool|
      tool.manifest = prune_manifest("old")
      tool.apply_kustomize(prune_app, "foundation")
      tool.manifest = prune_manifest("new")
      tool.fail_apply = true
      expect_raises(Exception, /apply failed/) { tool.apply_kustomize(prune_app, "foundation") }
      tool.deletions.should be_empty
      tool.inventory["entries"].as_a.map { |entry| entry["name"].as_s }.should eq(%w(old new))
      tool.objects["v1/ConfigMap/helper-inventory"]["metadata"]["annotations"][Kube::Helper::Pruning::PRUNE_LOCK]?.should be_nil
      tool.fail_apply = false
      tool.apply_kustomize(prune_app, "foundation")
      tool.objects.has_key?("v1/ConfigMap/old").should be_false
    end
  end

  it "retains stale entries after deletion failure and retries safely" do
    with_pruning_fixture do |tool|
      tool.manifest = prune_manifest("old")
      tool.apply_kustomize(prune_app, "foundation")
      tool.manifest = ""
      tool.fail_delete = true
      expect_raises(Exception, /deletion failed/) { tool.apply_kustomize(prune_app, "foundation") }
      tool.inventory["entries"].as_a.size.should eq(1)
      tool.fail_delete = false
      tool.apply_kustomize(prune_app, "foundation")
      tool.inventory["entries"].as_a.should be_empty
    end
  end

  it "rejects foreign desired objects before apply and never implicitly adopts copied ownership" do
    with_pruning_fixture do |tool|
      tool.seed("foreign", foreign: true)
      tool.manifest = prune_manifest("foreign")
      expect_raises(Exception, /foreign or replaced/) { tool.apply_kustomize(prune_app, "foundation") }
      tool.calls.any? { |args| args.includes?("apply") || args.includes?("delete") }.should be_false
      tool.manifest = prune_manifest("new")
      copied = tool.seed("new")
      copied["metadata"]["annotations"].as_h[Kube::Helper::Pruning::PRUNE_OWNER] = JSON::Any.new(tool.owner)
      expect_raises(Exception, /unrecorded prune ownership/) { tool.apply_kustomize(prune_app, "foundation") }
    end
  end

  it "rejects replacement inventory even when its data and scope marker were copied" do
    with_pruning_fixture do |tool|
      tool.manifest = prune_manifest("old")
      tool.apply_kustomize(prune_app, "foundation")
      tool.touch(tool.objects["v1/ConfigMap/helper-inventory"], replace_uid: true)
      tool.calls.clear
      tool.manifest = ""
      expect_raises(Exception, /foreign or replaced prune inventory/) { tool.apply_kustomize(prune_app, "foundation") }
      tool.calls.any? { |args| args.includes?("apply") || args.includes?("delete") || args.includes?("patch") }.should be_false
    end
  end

  it "rejects replaced stale targets even if ownership markers were copied" do
    with_pruning_fixture do |tool|
      tool.manifest = prune_manifest("old")
      tool.apply_kustomize(prune_app, "foundation")
      tool.touch(tool.objects["v1/ConfigMap/old"], replace_uid: true)
      tool.manifest = ""
      expect_raises(Exception, /replaced prune target/) { tool.apply_kustomize(prune_app, "foundation") }
      tool.deletions.should be_empty
    end
  end

  it "lets native UID/resourceVersion deletion preconditions reject a replacement race" do
    with_pruning_fixture do |tool|
      tool.manifest = prune_manifest("old")
      tool.apply_kustomize(prune_app, "foundation")
      tool.manifest = ""
      tool.race_delete = true
      expect_raises(Exception, /delete precondition failed/) { tool.apply_kustomize(prune_app, "foundation") }
      tool.objects.has_key?("v1/ConfigMap/old").should be_true
      tool.inventory["entries"].as_a.size.should eq(1)
    end
  end

  it "guards desired apply against concurrent updates" do
    with_pruning_fixture do |tool|
      tool.seed("keep")
      tool.manifest = prune_manifest("keep")
      tool.race_apply = true
      expect_raises(Exception, /apply conflict/) { tool.apply_kustomize(prune_app, "foundation") }
      tool.deletions.should be_empty
    end
  end

  it "does not delete an adopted legacy object if apply fails before its ownership claim" do
    with_pruning_fixture do |tool|
      tool.seed("keep")
      tool.manifest = prune_manifest("keep")
      tool.fail_apply = true
      expect_raises(Exception, /apply failed/) { tool.apply_kustomize(prune_app, "foundation") }
      tool.fail_apply = false
      tool.manifest = ""
      tool.apply_kustomize(prune_app, "foundation")
      tool.objects.has_key?("v1/ConfigMap/keep").should be_true
      tool.deletions.should be_empty
    end
  end

  it "fails closed on interrupted uncommitted creates and prior writer locks" do
    with_pruning_fixture do |tool|
      tool.manifest = prune_manifest("new")
      tool.fail_save_after_create = true
      expect_raises(Exception, /interrupted save/) { tool.apply_kustomize(prune_app, "foundation") }
      tool.fail_save_after_create = false
      expect_raises(Exception, /uncommitted prune creation/) { tool.apply_kustomize(prune_app, "foundation") }
      tool.objects["v1/ConfigMap/helper-inventory"]["metadata"]["annotations"].as_h[Kube::Helper::Pruning::PRUNE_LOCK] = JSON::Any.new({"token" => "prior-writer", "expires" => Time.utc.to_unix + 120}.to_json)
      expect_raises(Exception, /inventory is busy/) { tool.apply_kustomize(prune_app, "foundation") }
      tool.deletions.should be_empty
    end
  end

  it "takes over an expired lease without manual lock cleanup" do
    with_pruning_fixture do |tool|
      tool.manifest = prune_manifest("keep")
      tool.apply_kustomize(prune_app, "foundation")
      inventory_object = tool.objects["v1/ConfigMap/helper-inventory"]
      inventory_object["metadata"]["annotations"].as_h[Kube::Helper::Pruning::PRUNE_LOCK] = JSON::Any.new({"token" => "crashed-writer", "expires" => Time.utc.to_unix - 1}.to_json)
      tool.touch(inventory_object)
      tool.apply_kustomize(prune_app, "foundation")
      inventory_object = tool.objects["v1/ConfigMap/helper-inventory"]
      inventory_object["metadata"]["annotations"][Kube::Helper::Pruning::PRUNE_LOCK]?.should be_nil
      tool.inventory["entries"][0]["name"].as_s.should eq("keep")
    end
  end

  it "fences an apply that completes after lease takeover before any stale delete" do
    with_pruning_fixture do |tool|
      tool.manifest = prune_manifest("keep", "old")
      tool.apply_kustomize(prune_app, "foundation")
      tool.manifest = prune_manifest("keep")
      tool.takeover_apply = true
      expect_raises(Exception, /fixture precondition failed/) { tool.apply_kustomize(prune_app, "foundation") }
      tool.deletions.should be_empty
      tool.objects.has_key?("v1/ConfigMap/old").should be_true
      JSON.parse(tool.objects["v1/ConfigMap/helper-inventory"]["metadata"]["annotations"][Kube::Helper::Pruning::PRUNE_LOCK].as_s)["token"].as_s.should eq("successor")
    end
  end

  it "keeps dry run free of live reads/writes and rejects --delete before apply" do
    with_pruning_fixture do |tool|
      tool.manifest = prune_manifest("new")
      tool.dry_run = true
      tool.apply_kustomize(prune_app, "foundation")
      tool.objects.should be_empty
      tool.calls.size.should eq(2)
      tool.calls.last.should contain("--dry-run=client")
      tool.calls.clear
      tool.dry_run = false
      tool.deleting = true
      expect_raises(Exception, /does not support --delete/) { tool.apply_app(prune_app, "foundation") }
      tool.calls.should be_empty
    end
  end

  it "rejects unsafe scope/kinds and never tracks Tenant custom resources" do
    with_pruning_fixture do |tool|
      app = prune_app
      tool.manifest = prune_manifest("new")
      app.prune.not_nil!.kinds = ["product.example/v1/Tenant"]
      expect_raises(Exception, /explicit supported native kinds/) { tool.apply_kustomize(app, "foundation") }
      app.prune.not_nil!.kinds = ["v1/Secret"]
      expect_raises(Exception, /explicit supported native kinds/) { tool.apply_kustomize(app, "foundation") }
      app.prune.not_nil!.kinds = ["v1/ConfigMap"]
      tool.manifest = prune_manifest("new").sub("namespace: intent", "namespace: other")
      expect_raises(Exception, /explicit inventory namespace/) { tool.apply_kustomize(app, "foundation") }
      tool.objects.should be_empty
      tool.manifest = "apiVersion: product.example/v1\nkind: Tenant\nmetadata: {name: customer, namespace: intent}\n"
      tool.apply_kustomize(app, "foundation")
      tool.inventory["entries"].as_a.should be_empty
      tool.manifest = ""
      tool.apply_kustomize(app, "foundation")
      tool.objects.has_key?("product.example/v1/Tenant/customer").should be_true
      tool.deletions.should be_empty
    end
  end

  it "retains already-terminating stale targets until native absence without repeating deletion" do
    with_pruning_fixture do |tool|
      tool.manifest = prune_manifest("old")
      tool.apply_kustomize(prune_app, "foundation")
      tool.objects["v1/ConfigMap/old"]["metadata"].as_h["deletionTimestamp"] = JSON::Any.new("2026-11-12T00:00:00Z")
      tool.touch(tool.objects["v1/ConfigMap/old"])
      tool.manifest = ""
      tool.apply_kustomize(prune_app, "foundation")
      tool.deletions.should be_empty
      tool.inventory["entries"][0]["name"].as_s.should eq("old")
      tool.objects.delete("v1/ConfigMap/old")
      tool.apply_kustomize(prune_app, "foundation")
      tool.inventory["entries"].as_a.should be_empty
    end
  end

  it "retains accepted deletes awaiting finalizers and observes completion on subsequent runs" do
    with_pruning_fixture do |tool|
      tool.manifest = prune_manifest("old")
      tool.apply_kustomize(prune_app, "foundation")
      tool.manifest = ""
      tool.finalize_delete = true
      tool.apply_kustomize(prune_app, "foundation")
      tool.deletions.size.should eq(1)
      tool.inventory["entries"][0]["name"].as_s.should eq("old")
      tool.apply_kustomize(prune_app, "foundation")
      tool.deletions.size.should eq(1)
      tool.inventory["entries"].as_a.size.should eq(1)
      tool.objects.delete("v1/ConfigMap/old")
      tool.apply_kustomize(prune_app, "foundation")
      tool.inventory["entries"].as_a.should be_empty
    end
  end

  it "rejects desired terminating objects and foreign owner references" do
    with_pruning_fixture do |tool|
      object = tool.seed("keep")
      object["metadata"].as_h["deletionTimestamp"] = JSON::Any.new("2026-11-12T00:00:00Z")
      tool.manifest = prune_manifest("keep")
      expect_raises(Exception, /target is terminating/) { tool.apply_kustomize(prune_app, "foundation") }
      object["metadata"].as_h.delete("deletionTimestamp")
      object["metadata"].as_h["ownerReferences"] = JSON.parse("[{\"uid\":\"foreign\"}]")
      expect_raises(Exception, /foreign owner references/) { tool.apply_kustomize(prune_app, "foundation") }
      tool.calls.any? { |args| args.includes?("apply") || args.includes?("delete") }.should be_false
    end
  end

  it "rejects inventory collisions and List containers before any inventory operation" do
    with_pruning_fixture do |tool|
      tool.manifest = prune_manifest("helper-inventory")
      expect_raises(Exception, /cannot also be a desired target/) { tool.apply_kustomize(prune_app, "foundation") }
      tool.manifest = "apiVersion: v1\nkind: List\nitems: []\n"
      expect_raises(Exception, /not List containers/) { tool.apply_kustomize(prune_app, "foundation") }
      tool.objects.should be_empty
    end
  end

  it "does not change ordinary opt-out application behavior" do
    with_pruning_fixture do |tool|
      tool.manifest = prune_manifest("plain")
      app = AppOptions.from_yaml("name: plain\nkustomize: ./plain\n")
      tool.apply_kustomize(app, "foundation")
      tool.calls.size.should eq(2)
      tool.objects.has_key?("v1/ConfigMap/helper-inventory").should be_false
    end
  end
end
