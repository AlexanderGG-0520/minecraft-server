# Kubernetes Paper PVC Example

This example shows a minimal Paper server on Kubernetes using:

* An explicit `minecraft-paper` namespace.
* A `ReadWriteOnce` persistent volume claim mounted at `/data`.
* `TYPE=paper` and an explicit `VERSION`.
* RCON credentials from a Kubernetes Secret.
* `terminationGracePeriodSeconds: 240`.
* A readiness probe based on `/data/.ready`.
* Deployment strategy `Recreate`.
* A simple TCP `ClusterIP` Service for port `25565`.

It intentionally does not include S3/MinIO asset sync. Start here when you want to inspect the basic
Kubernetes lifecycle and volume pattern before adding object-storage-backed assets.

## Prerequisites

* A Kubernetes cluster with a default storage class or another way to satisfy the PVC.
* `kubectl` configured for the target cluster.
* Network exposure appropriate for your cluster if players need to connect from outside the cluster.

## Apply

Review and edit the manifests first, especially the RCON password in `secret-rcon.yaml`.

```bash
kubectl apply -f namespace.yaml
kubectl apply -f pvc.yaml
kubectl apply -f secret-rcon.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```

Or apply the directory:

```bash
kubectl apply -f examples/kubernetes/paper-pvc/
```

## Minecraft version

The example uses `VERSION=1.21.11` as a current Paper-compatible example version at the time this file
was written. Change the `VERSION` environment variable in `deployment.yaml` before creating or updating
the server.

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
survived its readiness delay. During termination the entrypoint TERM handler owns shutdown, so you should
not rely on `/data/.ready` being removed immediately during controlled termination; treat it primarily as
a startup-readiness signal in this configuration.

## Volume safety

The PVC stores the world and server data. Deleting the PVC may delete the world data depending on your
storage provider and reclaim policy. Treat PVC deletion as potentially destructive unless you have
verified backups and reclaim behavior.

## Related docs

* [Root README](../../../README.md)
* [Examples README](../../README.md)
