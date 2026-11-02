# xbps-impurifier

Emit native XBPS packages and indexed repositories backed by a shared atomic,
GC-rooted Nix profile at `/opt/nix/profile`. Original project code is MIT licensed.

```nix
let impurifier = inputs.xbps-impurifier.lib.xbps-impurifier { inherit pkgs; };
    app = impurifier.makePackage { pkg = pkgs.hello; };
in impurifier.makeRepository {
  packages = [ impurifier.runtimeXbps app.offline ];
}
```

`makePackage` returns `net` and `offline`. Individual constructors are
`makeXbps`, `makeNetXbps`, and `makeOfflineXbps`; `buildXbps` accepts a native
filesystem payload and raw metadata. `revision` defaults to `"1"`. Native
versions must be XBPS-compatible; override an incompatible upstream version.

Flavors share a native package name/version. Publish them in separate repository
channels or choose distinct revisions. Use one `-f` to reinstall when changing
transport at the same version; two `-f` flags overwrite protected configuration
and are not required here.

```sh
sudo xbps-install -R /path/to/offline-repository -y -f hello
sudo xbps-remove -y hello
```

Net packages use administrator-configured Nix caches. Offline packages contain
the complete local closure cache; import disables remote substitution and remote
builders. Neither changes global cache trust. The repository builder produces
native repodata with `xbps-rindex` and rejects duplicate artifact filenames.
Signing remains a separate repository-distribution operation.

`makeRuntimeXbps { nixDependency = "nix>=0"; pythonDependency = "python3>=0"; }`
keeps native dependency policy under consumer control. An existing Nix/Python
runtime is required. Providing Nix through an impure native package is deferred
installer work, not excluded from the project.

## Host integration

`configFiles`, `files`, `users`, `directories`, `lifecycle`, and `hardware` use the
shared core API. Native XBPS configuration protection owns edited files.

The default host backend is runit. Provide a native runscript:

```nix
runit.run = ./my-service.run;
```

Runscripts live under `/etc/sv/<name>`; `runit.serviceDir` selects the supervisor's
service directory (default `/var/service`). The consumer must have a running
`runsvdir` watching that directory. Default native host dependencies are
`runit>=0` and `busybox>=0`, the latter providing system account creation.
Consumers can override `hostDependencies`. Explicit `systemd.unit` or
`openrc.script` selects that supervisor and corresponding dependencies instead.

The shared service policies preserve administrator stops/disables during
upgrades. runit supports enabled-but-initially-stopped services using a temporary
`down` marker and waits for an actual supervisor connection. Retry preserves
that marker if the supervisor is absent. The runit adapter requires
`stopOnRemove = true` and does not support starting an unenabled service;
unsupported policy combinations fail during emission. Accounts and data remain
after removal.

Install/upgrade lifecycle hooks run after account/directory creation and profile
publication, before service activation. They must be idempotent because failure
can cause a retry. A native downgrade is also an upgrade event to these hooks.

## Native transaction semantics

INSTALL post actions run after native transaction unpacking. Repeated callbacks
on an identical intent set are no-ops, so a batch produces one effective profile
activation in the VM test. REMOVE post actions reconcile changed intent.
Failures are reported through XBPS configuration status; native unpacking and
profile/service changes are not one rollback transaction. Fix the cause and
reinstall/reconfigure the failed native package or reconcile explicitly.

Native drivers can request `/usr/sbin/nix-profile-engine reconcile` in their
post action after changing declared libraries. XBPS does not supply a general
arbitrary-file trigger here; otherwise reconcile explicitly after driver
updates. Immutable snapshots do not establish real GPU ABI/kernel compatibility.

## Verification

`nix flake check -L` covers native repository queries/dependency metadata,
reference-free artifact closures, engine contracts, and real XBPS transactions
inside QEMU. VM coverage includes offline repositories, failed substitution,
transport reinstallation, configuration protection, batching, lifecycle,
service accounts/directories, runit upgrade/admin/removal behavior, failed
supervisor attachment and recovery, cooperating driver upgrades and GC.

The fixture runs actual XBPS and runit under NixOS with a preinstalled Nix/Python
runtime. It does not claim to boot a complete Void installation or install Nix.
