require "uuid"
require "set"

# Generic, opt-in Kustomize inventory. No selector or live-kind enumeration is
# used: every observation names one object in the explicitly selected namespace.
module Kube::Helper::Pruning
  PRUNE_OWNER           = "kube-helper.alpha.kubernetes.io/prune-owner"
  PRUNE_SCOPE           = "kube-helper.alpha.kubernetes.io/prune-scope"
  PRUNE_LOCK            = "kube-helper.alpha.kubernetes.io/prune-lock"
  PRUNE_LEASE_SECONDS   = 120
  PRUNE_REQUEST_TIMEOUT = "30s"
  # Explicit native allow-list. Tenant/custom resources, Secrets, namespaces and
  # persistent storage cannot become prune targets through arbitrary kind text.
  PRUNE_RESOURCES = {
    "v1/ConfigMap"                             => "configmaps",
    "v1/Service"                               => "services",
    "v1/ServiceAccount"                        => "serviceaccounts",
    "apps/v1/Deployment"                       => "deployments",
    "apps/v1/DaemonSet"                        => "daemonsets",
    "apps/v1/StatefulSet"                      => "statefulsets",
    "batch/v1/Job"                             => "jobs",
    "batch/v1/CronJob"                         => "cronjobs",
    "rbac.authorization.k8s.io/v1/Role"        => "roles",
    "rbac.authorization.k8s.io/v1/RoleBinding" => "rolebindings",
    "networking.k8s.io/v1/NetworkPolicy"       => "networkpolicies",
    "policy/v1/PodDisruptionBudget"            => "poddisruptionbudgets",
  }

  struct PruneEntry
    include JSON::Serializable
    property kind : String
    property name : String
    property uid : String?
    property claimed : Bool = false

    def initialize(@kind, @name, @uid = nil, @claimed = false); end

    def key : String
      kind + "/" + name
    end
  end

  struct PruneInventory
    include JSON::Serializable
    property version : Int32 = 1
    property uid : String
    property scope : String
    property entries : Array(PruneEntry)

    def initialize(@uid, @scope, @entries); end
  end

  private def prune_name!(value : String)
    raise "invalid prune resource name" unless value.bytesize <= 253 && value.matches?(/\A[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\z/)
  end

  private def validate_prune!(options : PruneOptions)
    raise "prune does not support --delete; apply an empty desired set to remove inventoried objects" if opt(:delete) == true
    raise "invalid prune namespace" unless options.namespace.matches?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/)
    prune_name!(options.inventory)
    raise "prune requires explicit supported native kinds" if options.kinds.empty? || options.kinds.any? { |kind| !PRUNE_RESOURCES.has_key?(kind) }
  end

  private def prune_kubectl(args : Array(String))
    kubectl(args + ["--request-timeout=" + PRUNE_REQUEST_TIMEOUT])
  end

  private def prune_lease(token : String) : String
    {"token" => token, "expires" => Time.utc.to_unix + PRUNE_LEASE_SECONDS}.to_json
  end

  # Renew only the exact UID, version and token previously observed. A successor
  # acquiring an expired lease changes the ConfigMap version, fencing this writer
  # before further mutations. Object writes also carry native UID/RV guards.
  private def prune_fence(options : PruneOptions, object : JSON::Any, inventory : PruneInventory) : JSON::Any
    previous = prune_annotations(object)[PRUNE_LOCK].as_s
    token = JSON.parse(previous)["token"].as_s
    prune_patch(options, JSON.parse([
      {"op" => "test", "path" => "/metadata/uid", "value" => inventory.uid},
      {"op" => "test", "path" => "/metadata/resourceVersion", "value" => object["metadata"]["resourceVersion"].as_s},
      {"op" => "test", "path" => "/metadata/annotations/kube-helper.alpha.kubernetes.io~1prune-lock", "value" => previous},
      {"op" => "add", "path" => "/metadata/annotations/kube-helper.alpha.kubernetes.io~1prune-lock", "value" => prune_lease(token)},
    ].to_json))
  end

  private def prune_resource(kind : String) : String
    resource = PRUNE_RESOURCES[kind]? || raise "unsupported inventory prune kind"
    api = kind.rpartition('/')[0]
    api == "v1" ? resource : resource + "." + api.partition('/')[0]
  end

  private def prune_get(kind : String, name : String, namespace : String) : JSON::Any?
    result = prune_kubectl(["get", prune_resource(kind), name, "--namespace", namespace, "--ignore-not-found", "-o", "json"])
    output = result[:output]
    return nil if output.strip.empty?
    object = JSON.parse(output)
    metadata = object["metadata"]
    raise "invalid live prune identity" unless metadata["name"].as_s == name && metadata["namespace"].as_s == namespace && !metadata["uid"].as_s.empty? && !metadata["resourceVersion"].as_s.empty?
    raise "unexpected live prune kind" unless object["apiVersion"].as_s + "/" + object["kind"].as_s == kind
    object
  end

  private def prune_annotations(object : JSON::Any) : JSON::Any
    metadata = object["metadata"].as_h
    metadata["annotations"] ||= JSON.parse("{}")
  end

  private def prune_file_command(verb : String, object : JSON::Any, field_manager : String? = nil) : JSON::Any
    file = File.tempfile("kube-helper-inventory", ".json")
    begin
      File.write(file.path, object.to_json)
      args = [verb, "-f", file.path, "-o", "json"]
      args << "--field-manager=#{field_manager}" if field_manager
      JSON.parse(prune_kubectl(args)[:output])
    ensure
      file.delete
    end
  end

  private def prune_patch(options : PruneOptions, operations : JSON::Any) : JSON::Any
    JSON.parse(prune_kubectl(["patch", "configmap", options.inventory, "--namespace", options.namespace, "--type=json", "-p", operations.to_json, "-o", "json"])[:output])
  end

  private def prune_owner!(object : JSON::Any, uid : String, group : String, app : String, may_adopt = false, allow_terminating = false)
    annotations = prune_annotations(object)
    owner = annotations[PRUNE_OWNER]?.try(&.as_s)
    # First-time adoption is limited to desired objects already stamped by this
    # exact helper application. Omitted historical objects are never discovered.
    legacy = annotations["kube-helper.alpha.kubernetes.io/group"]?.try(&.as_s) == group && annotations["kube-helper.alpha.kubernetes.io/name"]?.try(&.as_s) == app
    raise "foreign or replaced prune object #{object["metadata"]["name"]}" unless owner == uid || (may_adopt && owner.nil? && legacy)
    raise "prune target is terminating" if !allow_terminating && object["metadata"]["deletionTimestamp"]?
    raise "prune target has foreign owner references" if object["metadata"]["ownerReferences"]?.try { |owners| !owners.as_a.empty? }
  end

  private def prune_save(options : PruneOptions, object : JSON::Any, inventory : PruneInventory) : JSON::Any
    object = prune_fence(options, object, inventory)
    object["data"].as_h["inventory.json"] = JSON::Any.new(inventory.to_json)
    prune_file_command("replace", object)
  end

  private def apply_pruned_kustomize(manifest : String, path : String, ks_path : String, app : String, group : String, options : PruneOptions, field_manager : String?, force_conflicts : Bool)
    validate_prune!(options)
    scope = {group, app}.to_json
    documents = YAML.parse_all(manifest).reject { |doc| doc.raw.nil? }.map { |doc| JSON.parse(doc.to_json) }
    desired = [] of PruneEntry
    documents.each do |object|
      raise "prune requires individual objects, not List containers" if object["kind"].as_s.ends_with?("List")
      kind = object["apiVersion"].as_s + "/" + object["kind"].as_s
      next unless options.kinds.includes?(kind)
      metadata = object["metadata"]
      raise "desired prune metadata cannot declare UID/resourceVersion/ownerReferences" if {"uid", "resourceVersion", "ownerReferences", "deletionTimestamp"}.any? { |key| metadata[key]? }
      raise "desired prune ownership annotation is reserved" if prune_annotations(object)[PRUNE_OWNER]?
      name = metadata["name"].as_s
      prune_name!(name)
      raise "prune targets require the explicit inventory namespace" unless metadata["namespace"]?.try(&.as_s) == options.namespace
      raise "prune inventory cannot also be a desired target" if kind == "v1/ConfigMap" && name == options.inventory
      raise "duplicate desired prune target" if desired.any? { |entry| entry.key == kind + "/" + name }
      desired << PruneEntry.new(kind, name)
    end
    # Dry run validates/render-applies desired bytes only, without inventory reads,
    # claims, locks, stale observations or deletion.
    if dry_run?
      apply_file(path, ks_path, field_manager, force_conflicts) unless documents.empty?
      return
    end

    raise "prune ownership annotations are reserved" if {PRUNE_OWNER, PRUNE_SCOPE, PRUNE_LOCK}.any? { |key| config.annotations.has_key?(key) }
    token = UUID.random.to_s
    lock = prune_lease(token)
    object = prune_get("v1/ConfigMap", options.inventory, options.namespace)
    created = object.nil?
    if object
      inventory = PruneInventory.from_json(object["data"]["inventory.json"].as_s)
      raise "foreign or replaced prune inventory" unless inventory.version == 1 && inventory.scope == scope && inventory.uid == object["metadata"]["uid"].as_s && prune_annotations(object)[PRUNE_SCOPE]?.try(&.as_s) == scope
      raise "prune inventory is terminating" if object["metadata"]["deletionTimestamp"]?
      raise "prune inventory has foreign owner references" if object["metadata"]["ownerReferences"]?.try { |owners| !owners.as_a.empty? }
      if previous = prune_annotations(object)[PRUNE_LOCK]?
        lease = JSON.parse(previous.as_s)
        raise "prune inventory is busy; retry after its bounded lease expires" if lease["expires"].as_i64 > Time.utc.to_unix
      end
      operations = JSON.parse([
        {"op" => "test", "path" => "/metadata/uid", "value" => inventory.uid},
        {"op" => "test", "path" => "/metadata/resourceVersion", "value" => object["metadata"]["resourceVersion"].as_s},
        {"op" => "add", "path" => "/metadata/annotations/kube-helper.alpha.kubernetes.io~1prune-lock", "value" => lock},
      ].to_json)
      object = prune_patch(options, operations)
    else
      # Create, never apply/upsert, so competing/foreign inventories cannot be
      # overwritten. A crash before UID initialization leaves a fail-closed CM.
      object = prune_file_command("create", JSON.parse({
        "apiVersion" => "v1", "kind" => "ConfigMap",
        "metadata" => {"name" => options.inventory, "namespace" => options.namespace,
                       "annotations" => {PRUNE_SCOPE => scope, PRUNE_LOCK => lock}},
        "data" => {"inventory.json" => "{}"},
      }.to_json))
      inventory = PruneInventory.new(object["metadata"]["uid"].as_s, scope, [] of PruneEntry)
    end

    begin
      object = prune_save(options, object, inventory) if created
      # Validate the complete old inventory before writes or deletes; changing an
      # allow-list cannot silently abandon previously owned objects.
      seen = Set(String).new
      inventory.entries.each do |entry|
        prune_name!(entry.name)
        raise "inventory kind is outside selected prune kinds" unless options.kinds.includes?(entry.kind)
        raise "invalid or duplicate inventory entry" unless seen.add?(entry.key) && !(entry.kind == "v1/ConfigMap" && entry.name == options.inventory)
      end
      # Every known object remains bound to its native UID. An interrupted
      # create without a committed UID fails closed rather than trusting copied
      # annotations. Unclaimed legacy objects are never stale-deleted.
      prior = inventory.entries.compact_map do |entry|
        live = prune_get(entry.kind, entry.name, options.namespace)
        if live
          raise "uncommitted prune creation #{entry.name}; inspect the inventory before recovery" unless entry.uid
          uid = live["metadata"]["uid"].as_s
          raise "replaced prune target #{entry.name}" if entry.uid != uid
          prune_owner!(live, inventory.uid, group, app, may_adopt: !entry.claimed, allow_terminating: !desired.any? { |item| item.key == entry.key })
          owned = prune_annotations(live)[PRUNE_OWNER]?.try(&.as_s) == inventory.uid
          next if !owned && !desired.any? { |item| item.key == entry.key }
          PruneEntry.new(entry.kind, entry.name, uid, owned)
        else
          entry
        end
      end
      desired.each_with_index do |entry, index|
        if live = prune_get(entry.kind, entry.name, options.namespace)
          known = prior.find { |item| item.key == entry.key }
          owned = prune_annotations(live)[PRUNE_OWNER]?.try(&.as_s) == inventory.uid
          raise "unrecorded prune ownership #{entry.name}" if owned && (!known || known.uid != live["metadata"]["uid"].as_s)
          prune_owner!(live, inventory.uid, group, app, may_adopt: true)
          desired[index] = PruneEntry.new(entry.kind, entry.name, live["metadata"]["uid"].as_s, owned)
        end
      end
      # Persist the union before apply. Nil UIDs are pending creates; a live
      # object without a recorded UID requires explicit verified recovery. Failed/partial apply cannot
      # discard the previous inventory or make successfully created objects lost.
      pending = prior.reject { |entry| desired.any? { |item| item.key == entry.key } } + desired
      inventory.entries = pending
      object = prune_save(options, object, inventory)
      documents.each do |document|
        kind = document["apiVersion"].as_s + "/" + document["kind"].as_s
        next unless options.kinds.includes?(kind)
        name = document["metadata"]["name"].as_s
        index = desired.index { |entry| entry.kind == kind && entry.name == name }.not_nil!
        entry = desired[index]
        annotations = prune_annotations(document)
        annotations.as_h[PRUNE_OWNER] = JSON::Any.new(inventory.uid)
        annotations.as_h["kube-helper.alpha.kubernetes.io/group"] = JSON::Any.new(group)
        annotations.as_h["kube-helper.alpha.kubernetes.io/name"] = JSON::Any.new(app)
        if entry.uid
          live = prune_get(kind, name, options.namespace) || raise "desired prune object vanished before apply"
          raise "desired prune object replaced before apply" unless live["metadata"]["uid"].as_s == entry.uid
          prune_owner!(live, inventory.uid, group, app, may_adopt: !entry.claimed)
        else
          # Reserve an absent name with create, never an unguarded apply which
          # could overwrite a foreign object created since the preflight read.
          object = prune_fence(options, object, inventory)
          # Match kubectl apply's native default manager, avoiding an extra
          # kubectl-create owner which would conflict on the next changed apply.
          # kubernetes/kubectl pkg/cmd/apply/apply.go:GetApplyFieldManagerFlag
          manager = field_manager || (opt(:server_side) == true ? "kubectl" : "kubectl-client-side-apply")
          live = prune_file_command("create", document, manager)
          desired[index] = PruneEntry.new(kind, name, live["metadata"]["uid"].as_s, true)
          inventory.entries = prior.reject { |old| desired.any? { |item| item.key == old.key } } + desired
          object = prune_save(options, object, inventory)
        end
        # SSA/client apply must reject a concurrently updated or replaced object.
        document["metadata"].as_h["uid"] = live["metadata"]["uid"]
        document["metadata"].as_h["resourceVersion"] = live["metadata"]["resourceVersion"]
      end
      File.write(path, documents.map(&.to_json).join("\n---\n"))
      # An empty successfully rendered desired set is intentional: kubectl apply
      # rejects empty input, so there is no desired apply command in that case.
      unless documents.empty?
        object = prune_fence(options, object, inventory)
        apply_file(path, ks_path, field_manager, force_conflicts, PRUNE_REQUEST_TIMEOUT)
      end
      # Apply can outlive a lease; never start stale deletion after a successor
      # has taken over, even when that apply command eventually succeeded.
      object = prune_fence(options, object, inventory)
      desired = desired.map do |entry|
        live = prune_get(entry.kind, entry.name, options.namespace) || raise "desired prune object missing after apply"
        prune_owner!(live, inventory.uid, group, app)
        uid = live["metadata"]["uid"].as_s
        raise "desired prune object replaced during apply" if entry.uid && entry.uid != uid
        PruneEntry.new(entry.kind, entry.name, uid, true)
      end
      stale = prior.reject { |entry| desired.any? { |item| item.key == entry.key } }
      remaining = [] of PruneEntry
      stale.each do |entry|
        next unless entry.claimed
        object = prune_fence(options, object, inventory)
        next unless live = prune_get(entry.kind, entry.name, options.namespace)
        prune_owner!(live, inventory.uid, group, app, allow_terminating: true)
        uid = live["metadata"]["uid"].as_s
        raise "replaced stale prune target #{entry.name}" if entry.uid && entry.uid != uid
        if live["metadata"]["deletionTimestamp"]?
          remaining << entry
          next
        end
        api = entry.kind.rpartition('/')[0]
        prefix = api == "v1" ? "/api/v1" : "/apis/" + api
        uri = prefix + "/namespaces/" + options.namespace + "/" + PRUNE_RESOURCES[entry.kind] + "/" + entry.name
        file = File.tempfile("kube-helper-delete", ".json")
        begin
          File.write(file.path, {"apiVersion" => "v1", "kind" => "DeleteOptions", "preconditions" => {"uid" => uid, "resourceVersion" => live["metadata"]["resourceVersion"].as_s}}.to_json)
          prune_kubectl(["delete", "--raw", uri, "-f", file.path])
          # Accepted DELETE may only start finalization. Preserve native cleanup
          # authority until a later exact read proves the old object is absent.
          if pending = prune_get(entry.kind, entry.name, options.namespace)
            prune_owner!(pending, inventory.uid, group, app, allow_terminating: true)
            raise "stale prune target replaced after delete" unless pending["metadata"]["uid"].as_s == uid
            remaining << entry
          end
        ensure
          file.delete
        end
      end
      inventory.entries = desired + remaining
      object = prune_save(options, object, inventory)
    ensure
      # Failed commands retain the union. Ordinary failures release the lease;
      # killed processes expire automatically. A successor token is never cleared.
      begin
        current = prune_get("v1/ConfigMap", options.inventory, options.namespace) || raise "prune inventory disappeared"
        raise "prune inventory replaced" unless current["metadata"]["uid"].as_s == inventory.uid
        current_lock = prune_annotations(current)[PRUNE_LOCK].as_s
        raise "prune lease changed" unless JSON.parse(current_lock)["token"].as_s == token
        prune_patch(options, JSON.parse([
          {"op" => "test", "path" => "/metadata/uid", "value" => inventory.uid},
          {"op" => "test", "path" => "/metadata/resourceVersion", "value" => current["metadata"]["resourceVersion"].as_s},
          {"op" => "test", "path" => "/metadata/annotations/kube-helper.alpha.kubernetes.io~1prune-lock", "value" => current_lock},
          {"op" => "remove", "path" => "/metadata/annotations/kube-helper.alpha.kubernetes.io~1prune-lock"},
        ].to_json))
      rescue error
        logger.warn { "prune lock release failed: #{error.message}" }
      end
    end
  end
end
