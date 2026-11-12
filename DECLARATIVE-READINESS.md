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
