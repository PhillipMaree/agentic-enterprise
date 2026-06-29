# sealed-secrets (controller)

Installs the [Bitnami Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
controller into **`kube-system`** via the upstream chart (DIRECT-chart
convention: this dir holds only `values.yaml`, installed with `--repo`).

- Chart `sealed-secrets/sealed-secrets@2.17.9` == controller `0.33.1`,
  matched to the `kubeseal` CLI version in [docs/SECURITY.md](../../../docs/SECURITY.md).
- `deploy.sh` applies the committed dev sealing key
  ([secrets/dev/sealed-secrets-dev-keypair.yaml](../../../secrets/dev/sealed-secrets-dev-keypair.yaml))
  into `kube-system` **before** installing the controller, so the controller
  adopts a fixed key and committed `SealedSecret`s in
  [deploy/sealed-secrets/](../../sealed-secrets/) decrypt deterministically in
  every fresh kind cluster.
- The controller decrypts each `SealedSecret` into a normal Kubernetes
  `Secret` in the `enterprise-platform` namespace, which the stack charts
  consume by name.

> Dev-only. The committed sealing key is public — see
> [docs/SECURITY.md](../../../docs/SECURITY.md) for the posture and the prod
> rotation rule. Do not reuse this key outside local/CI.
