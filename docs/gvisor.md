# gVisor: a sandboxed runtime on every node

Every worker node has a second container runtime next to runc: [gVisor](https://gvisor.dev) (`runsc`). A pod that asks for it runs on
gVisor's user-space kernel instead of directly on the node's Linux kernel, so a kernel bug reached from inside the pod meets gVisor's
much smaller attack surface first. Nothing runs in gVisor by default: a workload opts in.

| Part | Where | Who |
|---|---|---|
| `runsc` and `containerd-shim-runsc-v1` on every node | `modules/eks-nodes` (cloud-init, at every boot) | Terraform |
| The containerd runtime handler named exactly `runsc` | `modules/eks-nodes` (a nodeadm `NodeConfig`) | Terraform |
| The Kubernetes `RuntimeClass` named `gvisor` (handler `runsc`) | the GitOps repository | GitOps |
| `runtimeClassName: gvisor` on a workload | the workload's chart | the workload |

## What Terraform does on a node

Two cloud-init parts, both before the part EKS adds for the managed node group:

1. **A script** (`modules/eks-nodes/gvisor-install.sh.tftpl`) downloads `gvisor.tar.bz2` of the pinned release from
   `storage.googleapis.com/gvisor/releases/release/<release>/x86_64/`, checks it against the **SHA-512** written in
   `platform.auto.tfvars` (`gvisor_sha512`, the value gVisor publishes in the `.sha512` file next to the tarball) and only then extracts
   it. `runsc`, the shim and the `gvisor-bin/` helper directory go to `/usr/local/bin`. On a mismatch the script stops before anything is
   installed; cloud-init reports the failure (`/var/log/cloud-init-output.log`) and the node has no `runsc`, so a pod that asks for gVisor
   fails to start instead of running unsandboxed. The script also writes `/etc/containerd/runsc.toml`: platform `systrap` and the systemd cgroup driver (the kubelet
   and containerd use it on Amazon Linux 2023).
2. **A nodeadm `NodeConfig`** whose inline containerd TOML adds the handler. nodeadm has no drop-in directory for this: it merges the
   inline `spec.containerd.config` into `/etc/containerd/config.toml` itself. Containerd 2.x (what Amazon Linux 2023 runs for Kubernetes 1.36) uses config version 3, whose CRI plugins are named `io.containerd.cri.v1.*`; nodeadm
picks that schema from the plugin name and rejects it on containerd 1.x, so a node on the wrong containerd fails to boot loudly:

```toml
[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runsc]
  runtime_type = 'io.containerd.runsc.v1'

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runsc.options]
  TypeUrl = 'io.containerd.runsc.v1.options'
  ConfigPath = '/etc/containerd/runsc.toml'
```

The order of the two does not matter: containerd looks for the shim only when a sandboxed pod starts. The release is installed again
on every new node, because the nodes are Spot instances that are replaced often and no custom image is built. A change of
`gvisor_release`, its checksum or the platform changes the launch template, so the node group replaces its nodes one at a time.

**Platform.** `systrap` (gVisor's default) needs neither KVM nor nested virtualization, so it works on ordinary, non-metal EC2 instances.
`kvm` would need bare metal. The value is written down (`gvisor_platform`) so that a change of gVisor's default cannot switch it.

**Updating.** Pick a release in `gs://gvisor/releases/release/`, download its `gvisor.tar.bz2` and `gvisor.tar.bz2.sha512`, check the one against the
other, and put the release and the checksum in `platform.auto.tfvars` together. (Releases up to `20260817.0` also published `runsc` and
the shim as separate files; newer ones publish the tarball only, which is why the node downloads that.) gVisor's own installation page
says its automatic download of missing helper binaries is going away, which is why `gvisor-bin/` comes from the tarball.

## How a workload opts in

```yaml
spec:
  runtimeClassName: gvisor      # the RuntimeClass object is created by GitOps (handler: runsc)
```

For reference, the object GitOps creates:

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
overhead:                       # the sandbox itself needs CPU and memory; the scheduler adds this to the pod's requests
  podFixed:
    cpu: 100m
    memory: 64Mi
```

## What cannot run in gVisor

gVisor re-implements the Linux system call interface; it is not Linux. A pod is **not** a candidate when it:

| Needs | Example here |
|---|---|
| `hostNetwork`, `hostPID`, `hostIPC` | the Cilium agent and operator, the Cilium Gateway's Envoy (`hostNetwork` on the gateway port), node-level agents |
| `privileged`, host devices, `hostPath` mounts of the node's own files or sockets | the Cilium agent (BPF filesystem, cgroups), the SPIRE agent (host PID view and the kubelet socket to attest workloads), the EBS CSI node plugin |
| eBPF, kernel modules, `perf`, unusual `sysctl`s, raw sockets | tracing and security agents (Tetragon, Falco-style tools), CNI and CSI plugins |
| Syscalls or `/proc` and `/sys` files gVisor does not implement | some databases tuned for Linux, anything that tunes the kernel; test the workload |
| Fast file or network I/O | still works, but file access goes through a gofer process and the network through gVisor's own stack: expect overhead on syscall-heavy and I/O-heavy workloads. Do not put the database server or other storage-heavy pods in it without measuring |

Good candidates: stateless, network-facing services and anything that runs untrusted or user-supplied code (a Backstage backend, scaffolder
jobs, CI-style job pods). The platform's own DaemonSets and the Gateway stay on runc.

## Cilium

The cluster uses Cilium as an overlay (VXLAN), without kube-proxy. A sandboxed pod still gets an ordinary network namespace and a veth pair
created by the CNI, and Cilium attaches its programs to the host side of that veth, so addressing, the VXLAN overlay and network policy keep
working. gVisor runs its own network stack in front of that interface, which has two consequences:

- Cilium's **socket-level load balancing** (it translates a Service address when the application calls `connect`) cannot see the
  sandboxed process' sockets, because they live in gVisor and not in the node's kernel. Service addresses are translated per packet on
  the veth instead. That is expected to work; verify it with a Service call from a sandboxed pod (below).
- The Cilium agent, the operator and the Gateway are not sandboxed (see the table above), so nothing about Cilium itself changes.

Mutual authentication (SPIFFE/SPIRE) is not enabled, so there is no SPIRE agent interaction to consider; when it is enabled, remember that
the SPIRE agent itself cannot be sandboxed.

## Spot nodes

The nodes are Spot instances. A replacement node boots without gVisor and installs it during cloud-init (a download of a few tens of MiB,
seconds when the NAT gateway is healthy). A sandboxed pod that is scheduled to a node in that short window fails to start
and is retried by the kubelet; run sandboxed workloads with at least two replicas. If `storage.googleapis.com` is unreachable, a new node comes up
without `runsc` and sandboxed pods stay in `ContainerCreating` on it (`kubectl describe pod` names the missing handler or shim).

## Verify

On a node (Session Manager):

```bash
runsc --version
cat /etc/containerd/runsc.toml
sudo grep -A6 'runtimes.runsc' /etc/containerd/config.toml
sudo journalctl -u containerd | grep -i runsc
```

In the cluster, once the RuntimeClass exists:

```bash
kubectl run gvisor-test --rm -it --restart=Never --image=busybox \
  --overrides='{"spec":{"runtimeClassName":"gvisor"}}' -- dmesg
```

Inside gVisor `dmesg` prints gVisor's own boot messages (for example `Starting gVisor...`) and the kernel version is not the node's
(`uname -r` shows the version gVisor reports, not the node's). On runc the same command shows the node's kernel log, or "Operation not permitted". To check that
Services work from the sandbox: `kubectl run ... --overrides=... -- wget -qO- http://<service>.<namespace>`.
