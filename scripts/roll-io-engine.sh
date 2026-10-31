#!/usr/bin/env bash
# Restart OpenEBS io-engine pods that are behind the DaemonSet's current
# template, one node at a time. The DaemonSet is OnDelete, so a chart upgrade
# leaves these pods on the old version until they are deleted.
#
# Before each node: workloads whose volumes have every replica on that node
# lose their storage while io-engine restarts. The script refuses to run while
# any exist unless --scale-down is given, which scales those workloads to 0
# for that node and restores them afterwards.
#
# After each node: waits until every pool and volume is Online with no
# rebuilds before moving on.
#
# Usage: scripts/roll-io-engine.sh [--dry-run] [--scale-down]
set -euo pipefail

ns="openebs"
ds="openebs-io-engine"
selector="app=io-engine,openebs.io/release=openebs"
healthy_timeout=1800 # seconds to wait for volumes after each node
settle_checks=3      # consecutive healthy checks, 20s apart, before moving on

dry_run=0
scale_down=0
for arg in "$@"; do
  case "${arg}" in
    --dry-run) dry_run=1 ;;
    --scale-down) scale_down=1 ;;
    *)
      echo "usage: $0 [--dry-run] [--scale-down]" >&2
      exit 2
      ;;
  esac
done

for cmd in kubectl jq; do
  command -v "${cmd}" >/dev/null || { echo "error: ${cmd} not found on PATH" >&2; exit 1; }
done
kubectl openebs --version >/dev/null 2>&1 || { echo "error: kubectl-openebs plugin not found on PATH" >&2; exit 1; }

log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*"; }
volumes_json() { kubectl openebs mayastor get volumes -n "${ns}" -o json; }
pools_json() { kubectl openebs mayastor get pools -n "${ns}" -o json; }

# Prints one line per problem; empty output means healthy. A failed or
# unparseable API call is reported as a problem, never as healthy.
unhealthy() {
  local pools volumes
  if ! pools="$(pools_json)" || ! volumes="$(volumes_json)"; then
    echo "mayastor API call failed"
    return 0
  fi
  echo "${pools}" | jq -r '.[] | select(.state.status != "Online") | "pool \(.id): \(.state.status)"' ||
    echo "can't parse pool list"
  # An unpublished volume (its workload scaled down) has no nexus, so only its
  # replicas are checked.
  echo "${volumes}" | jq -r '
    if length == 0 then "no volumes listed" else
    .[] | . as $v
    | ($v.state.replica_topology // {} | [.[]]) as $replicas
    | [
        (if ($replicas | length) != $v.spec.num_replicas then "\($replicas | length)/\($v.spec.num_replicas) replicas" else empty end),
        ($replicas[] | select(.state != "Online") | "replica on \(.node) \(.state)"),
        (if $v.state.target then
           (if $v.state.status != "Online" then "status \($v.state.status)" else empty end),
           (if ($v.state.target.rebuilds // 0) != 0 then "\($v.state.target.rebuilds) rebuilds" else empty end),
           ($v.state.target.children // [] | .[] | select(.state != "Online") | "nexus child \(.state)")
         else empty end)
      ]
    | select(length > 0)
    | "volume \($v.spec.uuid): \(join(", "))"
    end' || echo "can't parse volume list"
}

wait_healthy() {
  local deadline=$((SECONDS + healthy_timeout)) streak=0 problems
  while [ "${streak}" -lt "${settle_checks}" ]; do
    problems="$(unhealthy)"
    if [ -z "${problems}" ]; then
      streak=$((streak + 1))
    else
      streak=0
      if [ "${SECONDS}" -ge "${deadline}" ]; then
        echo "error: storage still unhealthy after ${healthy_timeout}s:" >&2
        echo "${problems}" >&2
        return 1
      fi
      log "waiting: $(echo "${problems}" | wc -l | tr -d ' ') problem(s), e.g. $(echo "${problems}" | head -1)"
    fi
    sleep 20
  done
}

# Workloads (kind/name in namespace, as "ns kind/name") using a volume with no
# replica outside the given node.
workloads_on_node() {
  local node="$1" volumes uuids pvcs
  volumes="$(volumes_json)" || exit 1
  uuids="$(echo "${volumes}" | jq -r --arg node "${node}" '
    .[] | select([.state.replica_topology // {} | .[] | select(.node != $node)] | length == 0) | .spec.uuid')"
  [ -n "${uuids}" ] || return 0
  pvcs="$(kubectl get pv -o json | jq -r --arg uuids "${uuids}" '
    ($uuids | split("\n")) as $u
    | .items[] | select(.spec.csi.volumeHandle as $h | $u | index($h))
    | "\(.spec.claimRef.namespace) \(.spec.claimRef.name)"')"
  echo "${pvcs}" | while read -r pvc_ns pvc; do
    kubectl get pods -n "${pvc_ns}" -o json | jq -r --arg pvc "${pvc}" '
      .items[] | select(any(.spec.volumes[]?; .persistentVolumeClaim.claimName == $pvc))
      | .metadata.ownerReferences[0] | "\(.kind)/\(.name)"' |
      while read -r owner; do
        case "${owner}" in
          StatefulSet/*) echo "${pvc_ns} statefulset/${owner#*/}" ;;
          ReplicaSet/*)
            echo "${pvc_ns} deployment/$(kubectl get rs -n "${pvc_ns}" "${owner#*/}" -o jsonpath='{.metadata.ownerReferences[0].name}')"
            ;;
          *)
            echo "error: pod using ${pvc_ns}/${pvc} is owned by ${owner}; can't scale it down" >&2
            exit 1
            ;;
        esac
      done
  done | sort -u
}

# Label selector for a workload's pods. Fails on an empty one, which would match
# every pod in the namespace.
pod_selector() {
  local sel
  sel="$(kubectl get -n "$1" "$2" -o json | jq -r '.spec.selector.matchLabels // {} | to_entries | map("\(.key)=\(.value)") | join(",")')"
  if [ -z "${sel}" ]; then
    echo "error: $1/$2 has no matchLabels selector; can't wait for its pods" >&2
    return 1
  fi
  echo "${sel}"
}

current_hash="$(kubectl get controllerrevision -n "${ns}" -o json | jq -r --arg ds "${ds}" '
  [.items[] | select(any(.metadata.ownerReferences[]?; .kind == "DaemonSet" and .name == $ds))]
  | max_by(.revision) | .metadata.labels["controller-revision-hash"]')"
nodes="$(kubectl get pods -n "${ns}" -l "${selector}" -o json | jq -r --arg h "${current_hash}" '
  .items[] | select(.metadata.labels["controller-revision-hash"] != $h) | .spec.nodeName' | sort)"

if [ -z "${nodes}" ]; then
  log "all ${ds} pods are on revision ${current_hash}"
  exit 0
fi

problems="$(unhealthy)"
if [ -n "${problems}" ]; then
  echo "error: storage is unhealthy; fix this before rolling:" >&2
  echo "${problems}" >&2
  exit 1
fi

blocked=0
for node in ${nodes}; do
  affected="$(workloads_on_node "${node}")"
  log "${node}: restart io-engine${affected:+; scale down: $(echo "${affected}" | tr '\n' ',' | sed 's/,$//')}"
  [ -n "${affected}" ] && blocked=1
  echo "${affected}" | while read -r w_ns w; do
    [ -z "${w}" ] || pod_selector "${w_ns}" "${w}" >/dev/null
  done
done
if [ "${blocked}" -eq 1 ] && [ "${scale_down}" -eq 0 ]; then
  echo "error: some workloads have every replica on a node being restarted; rerun with --scale-down" >&2
  exit 1
fi
[ "${dry_run}" -eq 1 ] && exit 0

# "ns kind/name replicas" lines still to restore; printed if the script dies.
scaled=""
restore_hint() {
  [ -n "${scaled}" ] || return 0
  echo "workloads left scaled down; restore once storage is healthy:" >&2
  echo "${scaled}" | while read -r w_ns w replicas; do
    echo "  kubectl scale -n ${w_ns} ${w} --replicas=${replicas}" >&2
  done
}
trap restore_hint EXIT

for node in ${nodes}; do
  affected="$(workloads_on_node "${node}")"
  if [ -n "${affected}" ]; then
    scaled="$(echo "${affected}" | while read -r w_ns w; do
      echo "${w_ns} ${w} $(kubectl get -n "${w_ns}" "${w}" -o jsonpath='{.spec.replicas}')"
    done)"
    echo "${scaled}" | while read -r w_ns w _; do
      sel="$(pod_selector "${w_ns}" "${w}")"
      log "${node}: scaling ${w_ns}/${w} to 0"
      kubectl scale -n "${w_ns}" "${w}" --replicas=0 >/dev/null
      until [ -z "$(kubectl get pods -n "${w_ns}" -l "${sel}" -o name)" ]; do sleep 5; done
    done
  fi

  old_pod="$(kubectl get pods -n "${ns}" -l "${selector}" --field-selector "spec.nodeName=${node}" -o jsonpath='{.items[0].metadata.name}')"
  log "${node}: deleting ${old_pod}"
  kubectl delete pod -n "${ns}" "${old_pod}" --wait=true >/dev/null

  new_pod=""
  until [ -n "${new_pod}" ]; do
    sleep 5
    new_pod="$(kubectl get pods -n "${ns}" -l "${selector}" --field-selector "spec.nodeName=${node}" -o json | jq -r --arg h "${current_hash}" '
      .items[] | select(.metadata.labels["controller-revision-hash"] == $h) | .metadata.name')"
  done
  kubectl wait -n "${ns}" --for=condition=Ready "pod/${new_pod}" --timeout=10m >/dev/null
  log "${node}: ${new_pod} ready; waiting for pools and volumes"
  wait_healthy

  if [ -n "${scaled}" ]; then
    echo "${scaled}" | while read -r w_ns w replicas; do
      log "${node}: scaling ${w_ns}/${w} back to ${replicas}"
      kubectl scale -n "${w_ns}" "${w}" --replicas="${replicas}" >/dev/null
      kubectl rollout status -n "${w_ns}" "${w}" --timeout=10m >/dev/null
    done
    scaled=""
    wait_healthy
  fi
  log "${node}: done"
done

log "all ${ds} pods are on revision ${current_hash}"
