# Declarative readiness source dependency

Requested outcome: generic native kube-helper support for source-defined Helm
readiness and desired CRD establishment. This supports Quantum's fresh-cluster
apply-once foundation without cluster-delivered orchestration scripts.

Repository: https://github.com/spoved/kube-helper. Standalone local source clone:
`/Volumes/data/codex/quantum/worktrees/kube-helper-declarative-20261111`.
Branch: `codex/declarative-reconciliation-20261111`, base v1.0.5 commit
`ac2a42f3cb7718835c4fc6b8144ebc165f72dda3`. Owner: delegated cluster/tool worker;
disposition active, lead owns local source handoff and any publication decision.
No upstream push or live operation is authorized.

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
