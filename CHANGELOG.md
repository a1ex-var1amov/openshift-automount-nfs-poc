# Changelog

## v1.2 (2025-09-15)
- Add SELinux host-policy option to enable browsing autofs mountpoints from pods:
  - selinux/allow-container-autofs.te (policy TE)
  - selinux/machineconfig-allow-container-autofs.yaml (MachineConfig template)
  - selinux/README.md with build/apply/verify instructions
- Add test-pod/selinux-test-userb-home.yaml validation pod:
  - Binds /var/mnt/home → /mnt/home and /var/mnt/home/userb → /home/userb
  - Works without init container when SELinux policy is applied
- Keep kustomize images tag-configurable; trim test overlay to working resources

## v1.1 (2025-09-14)
- Clean release of working solution:
  - Automount DaemonSet (host autofs + NFSv3)
  - Final test deployment test-pod-deploy-usera-live-nfs.yaml
  - Documentation: solution-final-complete.md, README-v1.1.md
- Remove experimental and obsolete manifests; keep repo minimal and production-ready
