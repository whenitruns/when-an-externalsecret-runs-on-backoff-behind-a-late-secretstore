#!/usr/bin/env bash
# Run Report #RR13, §4 (Reproduction). Every line of the report's §4 block appears below, in order and exactly as printed;
# each step then runs the commands its lines print, one step per invocation. `poll` runs the report's poll commands,
# printed for P1, once per call (the report repeats them every 5 s, and for the other schedules with rr13-p1 replaced —
# see README). The manifests rr13-p1*.yaml are the report's, byte for byte; step 0's printed sed line writes rr13-p0*,
# rr13-p2* and rr13-p3* from them (the same bytes are kept here).
#   ./reproduce.sh 0 | 1 | 2 | 3 | 4 | poll | 5
# Steps 2, 3 and 4 wait as the report's schedules do (sleep 60, then 540; step 4 also waits for the store) — run `poll` in
# a second terminal meanwhile. Exit codes: `kubectl wait` exits 1 when its timeout passes first; in `poll`, the two grep
# pipelines exit 1 when nothing matches (for example, no controller line for that schedule yet). The script runs under
# `set -uo pipefail` without `-e`, so a non-zero exit does not stop a step; it has no loops.
set -uo pipefail
cd "$(dirname "$0")"

step_0() {
# 0. Bring up a kind cluster (node Kubernetes v1.36.4) and install External Secrets Operator v2.11.0 from
#    the official chart, with the controller's log level at debug. Confirm the three pods are Ready. Then write
#    the P0, P2 and P3 files from the three printed P1 files (p1 replaced by p0, p2 or p3).
#      kind create cluster --name rr13 --image kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed
#      helm install external-secrets https://github.com/external-secrets/external-secrets/releases/download/helm-chart-2.11.0/external-secrets-2.11.0.tgz -n external-secrets --create-namespace --set log.level=debug --wait
#      kubectl -n external-secrets get pods
#      for p in p0 p2 p3; do for f in rr13-p1 rr13-p1-es rr13-p1-rbac; do sed "s/p1/$p/g" $f.yaml > ${f/p1/$p}.yaml; done; done
kind create cluster --name rr13 --image kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed
helm install external-secrets https://github.com/external-secrets/external-secrets/releases/download/helm-chart-2.11.0/external-secrets-2.11.0.tgz -n external-secrets --create-namespace --set log.level=debug --wait
kubectl -n external-secrets get pods
for p in p0 p2 p3; do for f in rr13-p1 rr13-p1-es rr13-p1-rbac; do sed "s/p1/$p/g" $f.yaml > ${f/p1/$p}.yaml; done; done
}

step_1() {
# 1. P0 (control): the store side and its permission; once the store is Ready, the ExternalSecret.
#      kubectl apply -f rr13-p0.yaml -f rr13-p0-rbac.yaml
#      kubectl -n rr13-p0 wait --for=condition=Ready secretstore/rr13-k8s --timeout=120s
#      kubectl apply -f rr13-p0-es.yaml
kubectl apply -f rr13-p0.yaml -f rr13-p0-rbac.yaml
kubectl -n rr13-p0 wait --for=condition=Ready secretstore/rr13-k8s --timeout=120s
kubectl apply -f rr13-p0-es.yaml
}

step_2() {
# 2. P1: the store side and the ExternalSecret together (T0); the permission 60 s later.
#    Poll every 5 s (poll commands below) until the Secret has appeared. The permission line prints the time it returned.
#      kubectl apply -f rr13-p1.yaml -f rr13-p1-es.yaml
#      sleep 60; kubectl apply -f rr13-p1-rbac.yaml; date -u +%T.%3N
kubectl apply -f rr13-p1.yaml -f rr13-p1-es.yaml
sleep 60; kubectl apply -f rr13-p1-rbac.yaml; date -u +%T.%3N
}

step_3() {
# 3. P2: the store side (T0); the ExternalSecret at T0 + 60 s; the permission at T0 + 600 s.
#    Poll every 5 s until the Secret has appeared. The permission line prints the time it returned.
#      kubectl apply -f rr13-p2.yaml
#      sleep 60; kubectl apply -f rr13-p2-es.yaml
#      sleep 540; kubectl apply -f rr13-p2-rbac.yaml; date -u +%T.%3N
kubectl apply -f rr13-p2.yaml
sleep 60; kubectl apply -f rr13-p2-es.yaml
sleep 540; kubectl apply -f rr13-p2-rbac.yaml; date -u +%T.%3N
}

step_4() {
# 4. P3: the same schedule as P2; 10 s after the store turns Ready, change an annotation on the ExternalSecret.
#      kubectl apply -f rr13-p3.yaml
#      sleep 60; kubectl apply -f rr13-p3-es.yaml
#      sleep 540; kubectl apply -f rr13-p3-rbac.yaml
#      kubectl -n rr13-p3 wait --for=condition=Ready secretstore/rr13-k8s --timeout=1200s; sleep 10
#      kubectl -n rr13-p3 annotate externalsecret es-late force-sync=$(date +%s) --overwrite
kubectl apply -f rr13-p3.yaml
sleep 60; kubectl apply -f rr13-p3-es.yaml
sleep 540; kubectl apply -f rr13-p3-rbac.yaml
kubectl -n rr13-p3 wait --for=condition=Ready secretstore/rr13-k8s --timeout=1200s; sleep 10
kubectl -n rr13-p3 annotate externalsecret es-late force-sync=$(date +%s) --overwrite
}

poll() {
# Poll (every 5 s; shown for P1): the store's and the ExternalSecret's Ready condition, the target Secret,
# the ExternalSecret's events, the two work-queue metrics, and the controller's lines for the ExternalSecret.
#      kubectl -n rr13-p1 get secretstore rr13-k8s -o jsonpath='{.status.conditions[?(@.type=="Ready")]}{"\n"}'
#      kubectl -n rr13-p1 get externalsecret es-late -o jsonpath='{.status.conditions[?(@.type=="Ready")]}{"\n"}'
#      kubectl -n rr13-p1 get secret app-credentials-copy -o jsonpath='{.metadata.creationTimestamp}{"\n"}'
#      kubectl -n rr13-p1 get events --field-selector involvedObject.name=es-late -o custom-columns=LAST:.lastTimestamp,REASON:.reason,COUNT:.count,MESSAGE:.message
#      kubectl get --raw "/api/v1/namespaces/external-secrets/pods/$(kubectl -n external-secrets get pods -l app.kubernetes.io/name=external-secrets -o jsonpath='{.items[0].metadata.name}'):8080/proxy/metrics" | grep -E '^workqueue_(depth|retries_total)\{' | grep -E 'externalsecret|secretstore'
#      kubectl -n external-secrets logs deploy/external-secrets --timestamps | grep 'rr13-p1'
kubectl -n rr13-p1 get secretstore rr13-k8s -o jsonpath='{.status.conditions[?(@.type=="Ready")]}{"\n"}'
kubectl -n rr13-p1 get externalsecret es-late -o jsonpath='{.status.conditions[?(@.type=="Ready")]}{"\n"}'
kubectl -n rr13-p1 get secret app-credentials-copy -o jsonpath='{.metadata.creationTimestamp}{"\n"}'
kubectl -n rr13-p1 get events --field-selector involvedObject.name=es-late -o custom-columns=LAST:.lastTimestamp,REASON:.reason,COUNT:.count,MESSAGE:.message
kubectl get --raw "/api/v1/namespaces/external-secrets/pods/$(kubectl -n external-secrets get pods -l app.kubernetes.io/name=external-secrets -o jsonpath='{.items[0].metadata.name}'):8080/proxy/metrics" | grep -E '^workqueue_(depth|retries_total)\{' | grep -E 'externalsecret|secretstore'
kubectl -n external-secrets logs deploy/external-secrets --timestamps | grep 'rr13-p1'
}

step_5() {
# 5. Delete the test cluster (our cluster only).
#      kind delete cluster --name rr13
kind delete cluster --name rr13
}

case "${1:-}" in
  0) step_0 ;;
  1) step_1 ;;
  2) step_2 ;;
  3) step_3 ;;
  4) step_4 ;;
  poll) poll "$@" ;;
  5) step_5 ;;
  *) echo "usage: $0 0 | 1 | 2 | 3 | 4 | poll | 5  (one step per run; see README)"; exit 2 ;;
esac
