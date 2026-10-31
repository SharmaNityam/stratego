#!/usr/bin/env bash
set -euo pipefail

# One-time offline migration from the standalone Stratego database.
: "${KUBE_CONTEXT:?Set KUBE_CONTEXT to the intended kubectl context}"
NAMESPACE="${KUBE_NAMESPACE:-default}"
TARGET_CLUSTER="${TARGET_CLUSTER:-stratego-postgres-main-ha}"
BACKUP_DIR="${BACKUP_DIR:-data/backups}"
for name in "$NAMESPACE" "$TARGET_CLUSTER"; do
  if [[ ! "$name" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
    printf 'Invalid Kubernetes name: %s\n' "$name" >&2
    exit 2
  fi
done
kube=(kubectl --context "$KUBE_CONTEXT" --namespace "$NAMESPACE")
source_secret="$("${kube[@]}" get deployment stratego -o 'jsonpath={.spec.template.spec.containers[?(@.name=="stratego")].env[?(@.name=="DATABASE_URL")].valueFrom.secretKeyRef.name}')"
source_key="$("${kube[@]}" get deployment stratego -o 'jsonpath={.spec.template.spec.containers[?(@.name=="stratego")].env[?(@.name=="DATABASE_URL")].valueFrom.secretKeyRef.key}')"
replicas="$("${kube[@]}" get deployment stratego -o 'jsonpath={.spec.replicas}')"
if [[ "$source_secret" != stratego-db || "$source_key" != url || ! "$replicas" =~ ^[1-9][0-9]*$ ]]; then
  printf 'Expected a running app using the standalone stratego-db secret; refusing migration.\n' >&2
  exit 2
fi
"${kube[@]}" rollout status deployment/postgres --timeout=90s >/dev/null
"${kube[@]}" rollout status deployment/stratego --timeout=90s >/dev/null
"${kube[@]}" wait --for=condition=Ready "cluster/$TARGET_CLUSTER" --timeout=600s >/dev/null
ready="$("${kube[@]}" get "cluster/$TARGET_CLUSTER" -o 'jsonpath={.status.readyInstances}')"
if [[ "$ready" != 3 ]]; then
  printf 'Expected three ready PostgreSQL instances; found %s.\n' "$ready" >&2
  exit 2
fi
primary="$("${kube[@]}" get "cluster/$TARGET_CLUSTER" -o 'jsonpath={.status.currentPrimary}')"
[[ -n "$primary" ]]
target_secret="$TARGET_CLUSTER-app"
"${kube[@]}" get secret "$target_secret" >/dev/null
objects="$("${kube[@]}" exec "$primary" -c postgres -- psql -U postgres -d stratego -Atc "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p','v','m','S','f');")"
if [[ "$objects" != 0 ]]; then
  printf 'Target database is not empty; refusing to overwrite any data.\n' >&2
  exit 2
fi

umask 077
mkdir -p -- "$BACKUP_DIR"
backup="$(mktemp "$BACKUP_DIR/stratego-pg-$(date +%Y%m%d-%H%M%S)-XXXXXX")"
backup_complete=0
switched=0
completed=0
cleanup() {
  code=$?
  trap - EXIT
  if [[ "$completed" != 1 ]]; then
    if [[ "$switched" == 0 ]]; then
      printf 'Migration did not switch databases; restoring the original app replica count.\n' >&2
      "${kube[@]}" scale deployment/stratego --replicas="$replicas" >/dev/null || true
    else
      printf 'The app was switched to the new database; it will NOT be switched back automatically because new writes may exist. Inspect the deployment and both databases.\n' >&2
    fi
    if [[ "$backup_complete" == 1 ]]; then
      printf 'Backup retained at %s.\n' "$backup" >&2
    else
      printf 'Backup was not completed; do not use %s for recovery.\n' "$backup" >&2
    fi
  fi
  exit "$code"
}
trap cleanup EXIT

printf 'Pausing app writes for a consistent migration.\n'
"${kube[@]}" scale deployment/stratego --replicas=0 >/dev/null
attempt=0
while (( attempt < 90 )); do
  pods="$("${kube[@]}" get pods -l app=stratego -o name)"
  [[ -z "$pods" ]] && break
  sleep 1
  ((attempt+=1))
done
if [[ -n "$pods" ]]; then
  printf 'App pods did not stop; refusing to take an inconsistent backup.\n' >&2
  exit 1
fi
printf 'Creating a private local backup.\n'
"${kube[@]}" exec deployment/postgres -- pg_dump -U stratego --no-owner --no-privileges stratego > "$backup"
[[ -s "$backup" ]]
backup_complete=1
checksum_sql="SELECT count(*) || ':' || md5(coalesce(string_agg(row_to_json(x)::text, ',' ORDER BY x.id), '')) FROM (SELECT id,title,description,due_date,status,priority FROM public.tasks) x;"
source_check="$("${kube[@]}" exec deployment/postgres -- psql -U stratego -d stratego -Atc "$checksum_sql")"
printf 'Restoring into the new replicated database.\n'
# Restore as the application role so it owns tables and sequences, while using
# local postgres authentication without exposing application credentials.
"${kube[@]}" exec -i "$primary" -c postgres -- psql -U postgres -d stratego --single-transaction --set=ON_ERROR_STOP=1 -q -c 'SET ROLE stratego;' -f - < "$backup"
owner_check="$("${kube[@]}" exec "$primary" -c postgres -- psql -U postgres -d stratego -Atc "SELECT pg_get_userbyid(c.relowner) = 'stratego' AND has_table_privilege('stratego', c.oid, 'SELECT,INSERT,UPDATE,DELETE') FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname='tasks' AND c.relkind='r';")"
if [[ "$owner_check" != t ]]; then
  printf 'The application role cannot own or use the restored tasks table; leaving the app on the original database.\n' >&2
  exit 1
fi
target_check="$("${kube[@]}" exec "$primary" -c postgres -- psql -U postgres -d stratego -Atc "$checksum_sql")"
if [[ "$source_check" != "$target_check" ]]; then
  printf 'Task counts or checksums did not match; the app will remain on the original database.\n' >&2
  exit 1
fi
if [[ "$("${kube[@]}" get "cluster/$TARGET_CLUSTER" -o 'jsonpath={.status.currentPrimary}')" != "$primary" ]]; then
  printf 'The database primary changed during migration; leaving the app on the original database.\n' >&2
  exit 1
fi
# Wait for both replicas to replay the WAL position after the restore.
restore_lsn="$("${kube[@]}" exec "$primary" -c postgres -- psql -U postgres -d stratego -Atc 'SELECT pg_current_wal_lsn();')"
if [[ ! "$restore_lsn" =~ ^[0-9A-F]+/[0-9A-F]+$ ]]; then
  printf 'Could not verify the restore WAL position.\n' >&2
  exit 1
fi
caught_up=0
for ((attempt=0; attempt<120; attempt++)); do
  current_primary="$("${kube[@]}" get "cluster/$TARGET_CLUSTER" -o 'jsonpath={.status.currentPrimary}')"
  if [[ "$current_primary" != "$primary" ]]; then
    printf 'The database primary changed before replicas caught up.\n' >&2
    exit 1
  fi
  caught_up="$("${kube[@]}" exec "$primary" -c postgres -- psql -U postgres -d stratego -Atc "SELECT count(*) FROM pg_stat_replication WHERE state='streaming' AND replay_lsn >= '$restore_lsn'::pg_lsn;")"
  [[ "$caught_up" == 2 ]] && break
  sleep 1
done
if [[ "$caught_up" != 2 ]]; then
  printf 'Replicas did not catch up; leaving the app on the original database.\n' >&2
  exit 1
fi
printf 'Tasks match and both replicas caught up; switching the app to the replicated database.\n'
patch="{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"stratego\",\"env\":[{\"name\":\"DATABASE_URL\",\"valueFrom\":{\"secretKeyRef\":{\"name\":\"$target_secret\",\"key\":\"uri\"}}}]}]}}}}"
# The patch can succeed remotely even if the client loses its response; from
# this point, never automatically revert to a database that may become stale.
switched=1
"${kube[@]}" patch deployment stratego --type=strategic -p "$patch" >/dev/null
"${kube[@]}" scale deployment/stratego --replicas="$replicas" >/dev/null
"${kube[@]}" rollout status deployment/stratego --timeout=180s
completed=1
printf 'Migration complete. Backup retained at %s.\n' "$backup"
