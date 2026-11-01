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

if [[ "$DEPLOYMENT" != stratego || "$CONTAINER" != stratego ]]; then
  printf 'The AWS manifest overlay targets the stratego deployment and container.\n' >&2
  exit 2
fi

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

for resource in service/stratego horizontalpodautoscaler/stratego ingress/stratego; do
  "${kube[@]}" get "$resource" -o name >/dev/null
done

rendered="$(kubectl kustomize k8s/aws | sed "s|image: stratego-app:local|image: ${DEPLOY_IMAGE}|g")"
if ! grep -Fq "image: ${DEPLOY_IMAGE}" <<<"$rendered"; then
  printf 'Rendered manifests do not contain the requested image.\n' >&2
  exit 1
fi

printf 'Validating manifests for %s/%s in context %s.\n' "$NAMESPACE" "$DEPLOYMENT" "$KUBE_CONTEXT"
printf '%s\n' "$rendered" | "${kube[@]}" apply --dry-run=server -f - >/dev/null
printf 'Applying application, service, HPA and ingress manifests for %s.\n' "$DEPLOY_IMAGE"
if printf '%s\n' "$rendered" | "${kube[@]}" apply -f - && \
    "${kube[@]}" rollout status "deployment/$DEPLOYMENT" --timeout="$ROLLOUT_TIMEOUT"; then
  actual_image="$("${kube[@]}" get "deployment/$DEPLOYMENT" -o "jsonpath={.spec.template.spec.containers[?(@.name=='$CONTAINER')].image}")"
  if [[ "$actual_image" == "$DEPLOY_IMAGE" ]]; then
    printf 'Deployment completed and readiness probes passed.\n'
    exit 0
  fi
  printf 'Deployment image changed during rollout; refusing to overwrite it.\n' >&2
  exit 1
fi

printf 'Apply or rollout failed. Checking whether it is safe to restore the previous image. Other manifest changes may require manual review.\n' >&2
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
