# Kubernetes Paper S3-Compatible Asset Sync Example

This example shows a Paper server on Kubernetes using a persistent volume, RCON-based graceful shutdown,
and S3-compatible asset sync for plugins and configs.

It demonstrates:

* An explicit `minecraft-paper-minio` namespace.
* A `ReadWriteOnce` persistent volume claim mounted at `/data`.
* `TYPE=paper` and an explicit `VERSION`.
* RCON credentials from a Kubernetes Secret.
* S3-compatible credentials from a Kubernetes Secret.
* Plugins sync from an S3-compatible prefix.
* Configs sync from an S3-compatible prefix.
* `PLUGINS_REMOVE_EXTRA=false` and `CONFIGS_REMOVE_EXTRA=false`.
* `terminationGracePeriodSeconds: 240`.
* A readiness probe based on `/data/.ready`.
* Deployment strategy `Recreate`.
* A simple TCP `ClusterIP` Service for port `25565`.

This example intentionally does not include world archive install. It keeps asset sync focused on
plugins and configs.

## Prerequisites

* A Kubernetes cluster with a default storage class or another way to satisfy the PVC.
* `kubectl` configured for the target cluster.
* An S3-compatible endpoint, such as MinIO, Cloudflare R2, Garage, Backblaze B2, Wasabi, or AWS S3.
* A bucket and prefixes prepared for Paper plugins and configs.
* Network exposure appropriate for your cluster if players need to connect from outside the cluster.

## Expected S3 Layout

The manifests use these placeholder values:

```text
s3://minecraft-assets/paper/plugins/
s3://minecraft-assets/paper/configs/
```

Example object layout:

```text
minecraft-assets/
`-- paper/
    |-- plugins/
    |   |-- plugin-one.jar
    |   `-- plugin-two.jar
    `-- configs/
        |-- paper-global.yml
        |-- paper-world-defaults.yml
        `-- plugins/
            `-- plugin-one/
                `-- config.yml
```

Adjust `PLUGINS_S3_BUCKET`, `PLUGINS_S3_PREFIX`, `CONFIGS_S3_BUCKET`, and `CONFIGS_S3_PREFIX` in
`deployment.yaml` for your bucket layout.

## Credentials

`secret-rcon.yaml` provides the RCON password. `secret-s3.yaml` provides the endpoint and credentials.
The deployment maps those values to `S3_ENDPOINT_URL`, `AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY`, and `AWS_DEFAULT_REGION`.

Replace all placeholder values before applying these manifests. Do not commit real secrets. In a real
GitOps workflow, use your cluster's preferred secret management approach instead of storing plaintext
credentials in Git.

## Apply

Review and edit the manifests first, especially `secret-rcon.yaml`, `secret-s3.yaml`, the Minecraft
`VERSION`, and the S3 bucket/prefix values.

```bash
kubectl apply -f namespace.yaml
kubectl apply -f pvc.yaml
kubectl apply -f secret-rcon.yaml
kubectl apply -f secret-s3.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```

Or apply the directory:

```bash
kubectl apply -f examples/kubernetes/paper-minio-assets/
```

## Minecraft version

The example uses `VERSION=1.21.10` as a concrete Paper-compatible example version. Change the `VERSION`
environment variable in `deployment.yaml` before creating or updating the server.

Always review upstream Paper and Minecraft compatibility notes before changing versions, and make a
backup before upgrading an existing world.

## Exposing the server

`service.yaml` uses `type: ClusterIP` by default. Depending on your cluster, you may change the Service
to `LoadBalancer` or `NodePort`, or keep it internal and expose the server through your own ingress,
gateway, tunnel, or port-forwarding approach.

## Why `Recreate`

The Deployment uses `strategy.type: Recreate` because the world is stored on a single persistent volume.
Running multiple pods against the same world volume can corrupt state or create conflicting writes.
`Recreate` keeps the intended single-writer behavior clear.

## Why TERM handling and 240 seconds

Kubernetes sends TERM after beginning termination. `tini` forwards that signal to the entrypoint, whose
trap performs the Minecraft-aware RCON shutdown sequence. There is no `preStop` RCON command because its
runtime counts against the same grace period and would duplicate the shutdown path. The default modeled
bounded path is 219 seconds; 240 seconds adds a 21-second safety margin.

RCON is enabled explicitly and the password is read from `minecraft-rcon/password`. Replace the example
secret value before use.

## Why `/data/.ready`

The readiness probe checks for `/data/.ready`. The image creates this file only after the runtime has
survived its readiness delay, and removes it during shutdown. This lets Kubernetes stop routing traffic
to the pod during controlled termination.

## S3 Safety Notes

`PLUGINS_REMOVE_EXTRA=false` and `CONFIGS_REMOVE_EXTRA=false` are set explicitly in this example.
Remove-extra is disabled by default because it can remove local files that are not present in the
selected remote prefix.

Before enabling `*_REMOVE_EXTRA=true`, verify the bucket, endpoint, and prefix contain exactly the files
you expect. Never point remove-extra at an empty or wrong prefix. When enabled, the selected remote
prefix is treated as authoritative for that asset set.

Do not commit real S3 credentials, RCON passwords, tokens, or private URLs.

## Volume safety

The PVC stores the world and server data. Deleting the PVC may delete the world data depending on your
storage provider and reclaim policy. Treat PVC deletion as potentially destructive unless you have
verified backups and reclaim behavior.

## Related docs

* [Root README](../../../README.md)
* [Examples README](../../README.md)
