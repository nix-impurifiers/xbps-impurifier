# Testing

`nix flake check -L` runs emitter/native repository contracts, engine unit checks,
and actual XBPS/runit transactions in QEMU. The fixture disables networking and
asserts application closures are initially absent. It checks failure/recovery,
protected configs, transport changes, batching, lifecycle hooks, native accounts
and directories, runit admin intent/removal, stale supervisor control-state
recovery, cooperating drivers and GC. This is NixOS with real XBPS and runit,
not a full Void boot or Nix installer.

Change the shared core using temporary --override-input development pins. Run
the existing backend VM matrix for engine changes, then publish the core and
converge consumer pins before claiming the published build works.

The native-owned target-root VM installs two applications sharing immutable
objects, checks the actual XBPS installed-file database, deliberately alters a
payload and restores it, upgrades one application, retains the other, and removes
the final native closure. Executables run in a chroot with no Nix client, daemon
socket or Nix database. Exact dependencies and native automatic/orphan ownership
are exercised by the real XBPS solver. A separate bundled variant repeats the
original runit/host/lifecycle matrix with an incompatible external client and an
actual static private Nix fallback.
