#!/usr/bin/env bash
set -euo pipefail

# The runner must target an existing cluster and deployment explicitly.
: "${KUBE_CONTEXT:?Set KUBE_CONTEXT to the intended kubectl context}"
: "${DEPLOY_IMAGE:?Set DEPLOY_IMAGE to a registry image tagged with a full commit SHA}"
NAMESPACE="${KUBE_NAMESPACE:-default}"
DEPLOYMENT="${KUBE_DEPLOYMENT:-stratego}"
CONTAINER="${KUBE_CONTAINER:-stratego}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-180s}"

for resource_name in "$NAMESPACE" "$DEPLOYMENT" "$CONTAINER"; do
  if [[ ! "$resource_name" =~ ^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$ ]]; then
    printf 'Invalid Kubernetes resource name: %s\n' "$resource_name" >&2
    exit 2
  fi
done

if [[ ! "$DEPLOY_IMAGE" =~ ^[a-zA-Z0-9][a-zA-Z0-9._:/-]*:[a-f0-9]{40}$ ]]; then
  printf 'DEPLOY_IMAGE must end in a full 40-character lowercase commit SHA tag.\n' >&2
  exit 2
fi

kube=(kubectl --context "$KUBE_CONTEXT" --namespace "$NAMESPACE")
previous_image="$("${kube[@]}" get "deployment/$DEPLOYMENT" -o "jsonpath={.spec.template.spec.containers[?(@.name=='$CONTAINER')].image}")"
if [[ -z "$previous_image" || "$previous_image" == *' '* ]]; then
  printf 'Expected exactly one container named %s in deployment %s.\n' "$CONTAINER" "$DEPLOYMENT" >&2
  exit 2
fi

if [[ "$previous_image" == "$DEPLOY_IMAGE" ]]; then
  printf 'Deployment already uses %s; checking readiness.\n' "$DEPLOY_IMAGE"
  "${kube[@]}" rollout status "deployment/$DEPLOYMENT" --timeout="$ROLLOUT_TIMEOUT"
  exit
fi

printf 'Deploying %s to %s/%s in context %s.\n' "$DEPLOY_IMAGE" "$NAMESPACE" "$DEPLOYMENT" "$KUBE_CONTEXT"
"${kube[@]}" set image "deployment/$DEPLOYMENT" "$CONTAINER=$DEPLOY_IMAGE"
if "${kube[@]}" rollout status "deployment/$DEPLOYMENT" --timeout="$ROLLOUT_TIMEOUT"; then
  actual_image="$("${kube[@]}" get "deployment/$DEPLOYMENT" -o "jsonpath={.spec.template.spec.containers[?(@.name=='$CONTAINER')].image}")"
  if [[ "$actual_image" == "$DEPLOY_IMAGE" ]]; then
    printf 'Deployment completed and readiness probes passed.\n'
    exit 0
  fi
  printf 'Deployment image changed during rollout; refusing to overwrite it.\n' >&2
  exit 1
fi

printf 'Rollout failed. Checking whether it is safe to restore the previous image.\n' >&2
current_image="$("${kube[@]}" get "deployment/$DEPLOYMENT" -o "jsonpath={.spec.template.spec.containers[?(@.name=='$CONTAINER')].image}")"
if [[ "$current_image" != "$DEPLOY_IMAGE" ]]; then
  printf 'Another update changed the image; automatic rollback was not attempted.\n' >&2
  exit 1
fi
"${kube[@]}" set image "deployment/$DEPLOYMENT" "$CONTAINER=$previous_image"
if ! "${kube[@]}" rollout status "deployment/$DEPLOYMENT" --timeout="$ROLLOUT_TIMEOUT"; then
  printf 'Rollback did not become ready. Manual intervention is required.\n' >&2
fi
exit 1
