# When an `ExternalSecret` Runs on Backoff Behind a Late `SecretStore` — reproduction

When It Runs — Run Report #RR13 · Testing what infrastructure actually does.

Run Report: https://whenitruns.substack.com/p/when-an-externalsecret-runs-on-backoff

This repository holds the reproduction from the report above: the manifests printed in its §4 (Reproduction) — the three files for the P1 schedule, byte for byte, and, as the report says, the same three files with `p1` replaced by `p0`, `p2` or `p3` for the other schedules — and the commands its §4 prints, run one step at a time. Nothing here adds versions, configurations, or findings beyond the report.

## Setup pinned in the report

- External Secrets Operator v2.11.0, installed from the official Helm chart `external-secrets-2.11.0.tgz` (release asset of `helm-chart-2.11.0`; sha256 `8199b42fe80b871c6a86233a80bb14f599fd6e1e6462c1216d836577f845e161`), image `ghcr.io/external-secrets/external-secrets:v2.11.0` (`sha256:66fb710878cbf3eba4a927e35c5d75e29a202c9bab238aad64bfb23b786b962b`). The only chart value set is `log.level=debug`, so that the store's validation and the reconcile errors show up in the controller log with their times.
- A single-node `kind` cluster (kind v0.33.0) on a Linux test VM (GNU coreutils), node image `kindest/node:v1.36.4` (digest-pinned); `kubectl` v1.36.5.
- For each schedule, a `SecretStore` `rr13-k8s` using the `kubernetes` provider against the same cluster, authenticating as a service account whose permission to read the source Secret (a `Role` and a `RoleBinding`) is applied late, and an `ExternalSecret` `es-late` with `refreshInterval: 30s` and the default refresh policy.
- Verified on: lab measured 2026-09-28 on v2.11.0 (desk sources checked 2026-09-28 against v2.11.0) — re-verification against the then-current release happens at publication.

## Not scripted here

The report describes these without printing a command for them, so they are not scripted:

- the 5-second polling, and the polls of P0, P2 and P3 — `./reproduce.sh poll` runs the poll commands as printed (for P1) once; the report runs them every 5 seconds for each schedule, with `rr13-p1` replaced by that schedule's namespace, until its Secret has appeared;
- reading the retry times — the report takes the `ExternalSecret`'s failed attempts and the store's validations from the controller log (debug level) and compares their gaps with the 30-second `refreshInterval`.

## Files

| File | From the report |
|---|---|
| `rr13-p1.yaml` | §4 — the store side (two namespaces, the source Secret, the service account and the `SecretStore`), byte for byte |
| `rr13-p1-es.yaml` | §4 — the `ExternalSecret`, byte for byte |
| `rr13-p1-rbac.yaml` | §4 — the permission applied late (a `Role` and a `RoleBinding`), byte for byte |
| `rr13-p0*.yaml`, `rr13-p2*.yaml`, `rr13-p3*.yaml` | §4 — written by step 0's printed `sed` line from the three files above (`p1` replaced by `p0`, `p2` or `p3`); the same bytes are kept here |
| `reproduce.sh` | §4 — every line of its block, with the commands it prints, one step per run |

## Run order

On a test machine with `kind`, `helm` and `kubectl` as pinned above (all times UTC):

1. `./reproduce.sh 0` — create the `kind` cluster `rr13`, install External Secrets Operator v2.11.0 with the controller at log level `debug`, list the pods, and write the P0, P2 and P3 files.
2. `./reproduce.sh 1` — P0 (control): the store side and its permission, then the `ExternalSecret` once the store is `Ready`; poll (the P1 lines with `rr13-p0`) until the Secret has appeared.
3. `./reproduce.sh 2` — P1: the store side and the `ExternalSecret` together, the permission 60 seconds later (and the time it returned); meanwhile, in a second terminal, `./reproduce.sh poll` every 5 seconds until the Secret has appeared.
4. `./reproduce.sh 3` — P2: the store side, the `ExternalSecret` 60 seconds later, the permission 600 seconds after the store (and the time it returned); poll (with `rr13-p2`) every 5 seconds until the Secret has appeared.
5. `./reproduce.sh 4` — P3: as P2, then an annotation change on the `ExternalSecret` 10 seconds after the store turns `Ready`; poll (with `rr13-p3`) every 5 seconds until the Secret has appeared.
6. `./reproduce.sh 5` — delete the test cluster `rr13`.

## Expected observation

From the report (§3):

> **Design check (P1, before the permission):** in every poll before the permission (the last at T0 + 55 s), the store's `Ready` condition was `False` with the reason `InvalidProviderConfig`, and its events read `client is not allowed to get secrets` — the store was not ready, as the schedules require.

> **P0 — the store ready first (control):** the `ExternalSecret` was applied at 07:04:59.735 with its store already `Ready`; its first reconcile (07:04:59.763) created the Secret (07:04:59), and it re-synced every 30 seconds after that (07:05:29, 07:05:59, …), its `refreshInterval`.

> **P1 — together, permission at T0 + 60 s:** T0 = 07:06:05.5. The `ExternalSecret` failed at 07:06:05.527 and again 0.01 s later, then at 07:06:06.531, 07:06:10.534, 07:06:18.536, 07:06:34.540 and 07:07:06.541 — gaps of 1, 4, 8, 16 and 32 seconds (t₀ + 1, 5, 13, 29 and 61 s: one doubling step ahead of the sequence above, after the second failure) — each time with the reconcile error `error processing spec.data[0] (key: app-credentials), err: SecretStore "rr13-k8s" is not ready`. The permission was applied at 07:07:05.6 (T0 + 60 s); the store's next validation, at 07:07:06.568, succeeded, and its `Ready` condition turned `True` (07:07:06). The `ExternalSecret`'s attempt 27 ms earlier had still failed; its next came 64 seconds later, at 07:08:10.556, and created the Secret (07:08:10) — 64 seconds after the store became ready, 65 seconds after the permission. Until then its `Ready` condition was `False` with the reason `SecretSyncedError` and the message "could not get secret data from provider", and its events were `UpdateFailed` (7 times) with the error above.

> **P2 — store first, `ExternalSecret` at T0 + 60 s, permission at T0 + 600 s:** T0 = 07:09:16.2. The store's validation failed at T0 + 0.0 s (twice within 0.02 s), then at T0 + 1.0, 5.0, 13.0, 29.1, 61.1, 125.1, 253.1 and 509.1 s — gaps doubling from 1 to 256 seconds — each with `client is not allowed to get secrets`. The `ExternalSecret`, applied at 07:10:16.3, failed at 07:10:16.331 (and 0.01 s later), then at 07:10:17.335, 07:10:21.339, 07:10:29.342, 07:10:45.346, 07:11:17.350, 07:12:21.352, 07:14:29.355 and 07:18:45.357 — the same gaps, 1 to 256 seconds. The permission was applied at 07:19:16.7 (T0 + 600 s). Both sequences then waited 420 seconds, the 7-minute cap: the store's next validation, at 07:24:45.355, succeeded (`Ready` `True` at 07:24:45, 329 seconds after the permission), and the `ExternalSecret`'s next attempt, at 07:25:45.375, created the Secret (07:25:45) — 60 seconds after the store became ready and 389 seconds after the permission, with no reconcile of the `ExternalSecret` in between. Afterwards the store re-validated every 300 seconds (the 5-minute default).

> **P3 — an annotation change after the store is ready:** the same schedule as P2 (T0 = 07:26:47.0; the retries fell on the same gaps). The store became `Ready` at 07:42:16 (its validation at 07:42:16.099, T0 + 929 s); the annotation was changed at 07:42:26.0, and the Secret was created at 07:42:26 (the `ExternalSecret`'s reconcile at 07:42:26.067) — in the same second, 50 seconds before its next backoff retry was due (07:43:16, 420 seconds after its failure at 07:36:16.088).

> **Queue:** `workqueue_depth` was 0 in every poll of all four schedules, for the `ExternalSecret` and store controllers (and for the cluster-scoped ones).

> "Retried" in this section means a reconcile of `es-late` recorded in the controller log (a reconcile error while the store was not ready, or the successful sync); "the store became ready" means the time its `Ready` condition turned `True`; "the Secret appeared" means the target Secret's `creationTimestamp`.

The report's own limits (§6):

> **Other providers.** We made the store not ready with the `kubernetes` provider and a missing permission; stores that are not ready for other reasons, or cloud providers, were not measured.

> **`ClusterSecretStore` and the flood gate off.** We measured a namespaced `SecretStore` with the flood gate on (its default); a `ClusterSecretStore`, and `--enable-flood-gate=false`, were not measured.

> **A busy queue.** Our cluster had one `ExternalSecret` per schedule; how the backoff combines with a work queue that is also backed up was not measured.

> **Other versions.** Only v2.11.0 was measured; v2.12.0, v2.13.0, v2.14.0 and v2.15.0, released on 2026-10-06, 2026-10-16, 2026-10-23 and 2026-11-10, were not measured; v2.13.0, v2.14.0 and v2.15.0 include security fixes; the project supports only the current minor version, and its support table (`docs/introduction/stability-support.md` at v2.13.0) lists 2.11's end of life as 2026-10-06. The backoff's start comes from pull request #4339, not from a measurement.

> **A validation result of "unknown".** By the source, when the provider cannot even check its permissions, the store is marked ready with the reason `ValidationUnknown` and is not put on the backoff (`secretstore/common.go` L133–135, L199–204); we read this in the source only and did not measure it.

> **Long runs.** We watched each schedule until its Secret appeared; how the retries continue at the 7-minute cap over longer periods was followed for one cycle at most.

---

The team behind When It Runs maintains its own test environments and re-verifies findings when new releases change things; that is what the "Verified on" date means.

Licensed under the Apache License 2.0 — see `LICENSE`.
