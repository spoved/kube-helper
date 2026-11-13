# Declarative readiness source dependency

Requested outcome: generic native kube-helper support for source-defined Helm
readiness and desired CRD establishment. This supports Quantum's fresh-cluster
apply-once foundation without cluster-delivered orchestration scripts.

Repository: https://github.com/spoved/kube-helper. Standalone local source clone:
`/Volumes/data/codex/quantum/worktrees/kube-helper-declarative-20261111`.
Branch: `codex/declarative-reconciliation-20261111`, base v1.0.5 commit
`ac2a42f3cb7718835c4fc6b8144ebc165f72dda3`. Owner: delegated cluster/tool worker;
disposition active, lead owns local source handoff and any publication decision.
The lead has explicit DEV02 installation authority. Workers remain source/test-only;
no upstream push or publication is authorized.

Application options: `wait`, `atomic`, `timeout` select native Helm flags.
`wait_for_crds` on a Kustomize application waits for only CRD names enumerated
from its successfully rendered desired manifest. `timeout` also bounds this
native kubectl wait (default180s). Dry run performs no readiness observations.
These options do not select application tests or general product readiness.

`--capabilities` prints `declarative-readiness-v1` and exits before loading config,
selecting a context or invoking Kubernetes/Helm. Callers must require this explicit
capability rather than silently using an older binary which ignores YAML fields.

Server-side apply is independent of force-conflicts. `--server-side` sets SSA;
force stays false unless explicitly selected. Desired CRD names never come from
a live enumeration or UID lookup. Command failures stop the selected apply.

Validation:5 focused offline tests pass; CLI builds and --capabilities exits
without configuration or external command execution. Diff check passes. Source
is frozen for lead review; no commit, upstream push, publication or actual
installation. Local binary /tmp/kube-helper-declarative is test evidence only.

DEV02 readiness continuation: the lead has explicit installation authority;
workers remain source/test-only and no upstream push/publication is authorized.
`native-rollout-v1` extends per-app `wait: true` to desired native apps/v1
Deployment, DaemonSet and StatefulSet rollouts after successful Kustomize apply.
Targets are validated before applying. Explicit rendered metadata.namespace is
authoritative; omitted namespace keeps the same kubectl context default as apply,
without substituting app/group namespace. Timeout failures stop later actions.
Dry-run/delete perform no rollout wait. No product CR, endpoint query, sleeps,
retry loop or reconciliation is added. The lead reviews before binary build.

Rollout continuation validation:9 focused mocked tool checks pass, including all
three supported rollout kinds, explicit/context-default namespace selection,
actions/app ordering, timeout and apply failure propagation, target validation,
and opt-out/dry-run/delete behavior. Cluster's8 focused fixture checks pass,
including native wait declarations and older-capability refusal. Both diff checks
pass. No standalone binary build, commit, push, live or generated-k8s edit was
performed by the worker; lead review precedes build/publication decisions.

`scoped-field-manager-v1` adds a validated per-application `field_manager` for
Kustomize apply. It continues a deliberately selected existing SSA manager while
leaving `--force-conflicts=false` and every other application's manager
unchanged. This is generic apply ownership, not product reconciliation.

`scoped-authoritative-apply-v1` adds a per-application `force_conflicts` switch for
an explicitly authoritative Kustomize manifest. It never changes unrelated
applications and remains inert unless server-side apply is selected.

November12 scoped pruning continuation: current user authority supersedes the
historical publication/DEV02-only hold for the lead; the worker remains source
only. Task-owned worktree:
`/Volumes/data/codex/quantum/worktrees/kube-helper-pruning-20261112`, branch
`codex/scoped-kustomize-pruning-20261112`, base b711188, owner helper_pruning,
disposition active pending lead integration and cleanup. The original source
checkout remains shared and untouched. Requested finish line: opt-in generic
per-app inventory pruning, required source tests/review, lead publication and
DEV01 installation/acceptance. No worker live writes or push.

`scoped-kustomize-prune-v1` uses a namespaced ConfigMap inventory bound to its
native UID, exact per-object UID/resourceVersion protection, durable pending
state and a bounded 120-second serialization lease with CAS fencing. Only explicitly selected supported
native namespaced kinds are tracked; custom resources, Tenant, Secrets and
persistent storage are excluded. Successful desired apply precedes stale
removal; empty desired sets are supported. Initial inventory covers current
desired objects only. See SPEC.md for failure, interruption, dry-run, delete and
explicit recovery semantics. The capability does not perform product-level
reconciliation or historical discovery.

Pruning validation: full `crystal spec` passes 34 examples (22 scoped pruning,
12 existing readiness), covering desired initialization/omission/empty sets,
legacy provenance, create/apply/delete races and failures, UID-bound inventory
and target replacement, pending/expired/concurrent lease fencing, finalization
retention, scoped field managers, dry-run/delete, excluded custom resources and
ordinary opt-out behavior. CLI builds successfully; with PATH unavailable,
`--capabilities` exits without configuration/external commands and prints the
new capability alongside all existing ones. Format, JSON schema syntax and diff
checks pass. Local evidence: `/private/tmp/kube-helper-pruning-spec.log`,
`/private/tmp/kube-helper-pruning-build.log`; local binary:
`/private/tmp/kube-helper-pruning`. Compiler link warnings concern local macOS
27.2 object targets versus 27.0 deployment linking; tests/build both succeed.
The lead owns independent review, source publication, DEV01 acceptance and removal
of this task worktree/branch after integration; the original checkout is shared.

Independent-review delta: legacy desired adoption is allowed only while creating
an inventory, or for an already recorded same-native-UID unclaimed entry after
interrupted adoption. Later newly desired existing objects are rejected even
when their helper group/name provenance was copied. Two regression scenarios
cover rejection and safe same-UID retry. Full specs pass 36 examples (24 pruning,
12 readiness); CLI rebuild succeeds and reports version 1.1.0 plus all five
capabilities without external commands. The feature release bumps shard.yml only;
shard.lock dependencies are unchanged. Existing log/binary paths above now contain
this final candidate. Format and diff checks pass. Lead owns review delta and
publication; worker performed no push or live operation.

Native-review correction: the lead's disposable ConfigMap experiment demonstrated
that equal field-manager text does not migrate creation Update managedFields into
Apply ownership: a subsequent changed SSA conflicted. Reservation create now
uses native `--save-config` with its intended manager so kubectl can discover the
last-applied owner and perform its supported Update-to-Apply migration. It adds
no global force or managedFields clearing. Offline flag coverage includes default
SSA, custom SSA manager and client-side apply; full specs pass 37 examples (25
pruning, 12 readiness), and the v1.1.0 CLI rebuild passes. Native default/custom/
client-side changed-apply validation remains owned by the lead; these mocked
specs do not establish native managedFields semantics. Format/diff checks pass;
existing local log/binary paths contain this candidate. No worker live writes.
