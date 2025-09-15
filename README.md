# Automounting NFS on OpenShift

This *proof of concept* shows how to automount NFS shares on OpenShift.

This repo uses [openshift-toolbox](https://github.com/noseka1/openshift-toolbox) image.

## Deployment overview

![Deployment overview](docs/diagrams/openshift_automount_nfs_overview.svg "Deployment overview")

## Mount propagation

![Mount propagation](docs/diagrams/openshift_automount_nfs_mount_propagation.svg "Mount propagation")

## Deploying POC

Create a namespace where everything else will be deployed to:

```
$ oc apply --kustomize namespace
```

Unless you are bringing your own NFS server, you can deploy one on OpenShift:

```
$ oc apply --kustomize nfs-server
```

Obtain the IP address of the NFS server

```
$ oc get svc --namespace automount-nfs-poc nfs-server --output jsonpath='{.spec.clusterIP}'
```

Update the NFS IP address:

```
$ vi automount/extra.nfs
```

Deploy automount daemonset:

```
$ oc apply -k automount
```

Deploy a test pod:

```
$ oc apply --kustomize test-pod

### Optional: Deploy in-cluster LDAP with 5 users

```
$ oc apply --kustomize ldap
```

LDAP base: `dc=example,dc=org` with users `usera..usere` (UID/GID 2001..2005). The NFS server will auto-create `/exports/home/$USER` with UID/GID from LDAP if available.

Deploy two per-user test pods:

```
$ oc apply -k test-pod
```

This will create `test-pod-usera` and `test-pod-userb`. Each pod mounts `/home` and will see `/home/xyz` and its own home directory.

## Home directory automount (SSSD-like behavior)

This POC emulates sssd-based autofs home mapping for user UIDs/GIDs:

- Automount DaemonSet mounts NFS under `/var/mnt/home` using `extra.autofs` and `auto.home`.
- Pods mount host `/var/mnt/home` to `/home` with `HostToContainer` propagation.
- Users can see `/home/$USER` and other home directories as on a standard Linux system.

Steps:

1. Deploy NFS server and note ClusterIP, then update `automount/auto.home` to point at the IP.
2. The NFS server creates `/exports/home/{alice,bob,charlie}`; you can edit `nfs-server/users.csv` to define UIDs/GIDs and more users.
3. Deploy `automount` and `test-pod`. Set `runAsUser`/`runAsGroup` in your workload to the user’s UID/GID.

SELinux notes:

- NFS volumes are labeled with `context=system_u:object_r:container_file_t:s0` in `auto.home` so containers can access `/home/*` via HostPath.
- Mount propagation: DaemonSet `/mnt` is `Bidirectional`, pod mounts are `HostToContainer` as required.
```

## Optional: SELinux host policy (RHCOS) to enable browsing autofs parent

By default, containers (type `container_t`) cannot traverse the autofs root (`autofs_t`), so listing `/var/mnt/home` from pods fails even though individual submounts work. If you prefer host-level SELinux fix (no init container), apply the minimal policy in `selinux/`:

- `selinux/allow-container-autofs.te` (policy source)
- `selinux/machineconfig-allow-container-autofs.yaml` (MachineConfig template)
- `selinux/README.md` (build/apply/verify steps)

Quick steps:

1) Build policy package on a RHEL/Fedora host:
```
checkmodule -M -m -o allow-container-autofs.mod selinux/allow-container-autofs.te
semodule_package -o allow-container-autofs.pp -m allow-container-autofs.mod
BASE64_PP=$(base64 -w0 allow-container-autofs.pp)
```
2) Put `BASE64_PP` into `selinux/machineconfig-allow-container-autofs.yaml` (replace `<BASE64_OF_PP>`), then:
```
oc apply -f selinux/machineconfig-allow-container-autofs.yaml
oc get mcp; oc describe mcp worker   # wait until updated
```
3) Verify on a worker and from pods:
```
oc debug node/<worker>; chroot /host semodule -l | grep allow-container-autofs
oc exec -n automount-nfs-poc -l app=automount -- timeout 10 ls -la /var/mnt/home
```

Notes:
- Host-wide change; grants only read/traverse on `autofs_t` (least privilege).
- Alternative: pre-mount NFS on the node under a path labeled `container_file_t` and use HostPath in pods.

## Cleaning up

```
$ oc delete --kustomize namespace
```
## Video

[![How to Automount NFS on OpenShift](https://img.youtube.com/vi/QALt18puDPo/0.jpg)](http://www.youtube.com/watch?v=QALt18puDPo)

## TODO

* Automount doesn't seem to unmount unused volumes after a timeout

## References

* [Kubernetes Mount Propagation](https://medium.com/kokster/kubernetes-mount-propagation-5306c36a4a2d)
* [Mount propagation](https://kubernetes.io/docs/concepts/storage/volumes/#mount-propagation)
