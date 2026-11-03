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

## xbps-src templates

`makeTemplate { package = app.offline; sourceUrl = "https://example.org/hello.xbps"; }`
returns a native `template` and its original `INSTALL`/`REMOVE` inputs. Copy
these into `void-packages/srcpkgs/<native-package-name>/`, then run ordinary
`./xbps-src pkg <native-package-name>`. Publish the referenced XBPS artifact
at that URL first. The generated SHA256 checksum pins the exact artifact.

The recipe reads dependencies, provides, conflicts, replacements and protected
configuration from actual XBPS metadata. Native xbps-src verifies the download,
extracts the payload, regenerates package metadata and wraps the lifecycle
scripts. It preserves application payload bytes; compilation stays in Nix.
Stripping and automatic ELF dependency discovery are disabled because Nix
closures own those dependencies. The original native runtime requirements remain
enforced by XBPS. An original `noarch` artifact permits all xbps-src target
architectures; xbps-src emits its normal architecture-specific package.

The additional producer/consumer VM uses a pinned, complete upstream
void-packages tree and its native `ethereal` mode inside a disposable NixOS
VM. Actual SDK programs supply the FHS tool paths; upstream build hooks and
transaction clients are unchanged. `-I` skips source-build dependency setup
in that SDK fixture; a separate native install verifies missing runtime
requirements are rejected. The VM checks source corruption, native net/offline
recipe builds, two versions, configuration protection, package verification,
ordinary-user launch and GC retention/release. It does not claim a complete
Void bootstrap, cross compilation or remote package publication.

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

The exported `runtimeVersion` follows the pinned core source timestamp. Application dependencies require that runtime version or newer, rather than accepting every engine as `0.1.0`. This supports ordinary native engine upgrades without project release tags. Consumer-provided Nix dependency expressions remain independent of the engine's own native version.

### Native payloads without target-side Nix

`makeNativePackages { pkg; name ? pkg.pname; version ? pkg.version; ... }`
exports the complete closure as native-owned XBPS packages at its original store
paths. Each immutable object has one native package and exact reference
requirements. The application package owns command links. `programs` defaults to the main
command; use `[]` for a dependency-only payload. `binDir` defaults to `/usr/bin`.
Native XBPS handles
installation, checksums, dependencies, upgrades and orphan removal; these payloads
need no Nix executable, daemon or database. Keep native-owned objects separate
from a Nix-managed store and its garbage collection. This does not relocate files.
For producer-prepared system/prefix layouts, the existing `buildXbps { payload;
name; version; ... }` emits a native package without implicit impurifier hooks
or runtime requirements.

`makeRuntimeXbps` additionally accepts `bundledNixStore` and
`bundledNixNotices`. The supplied client must be a static ELF executable, and
upstream notices must be included. Bundling omits the default external Nix
dependency, retains Python, and uses the actual package architecture. A compatible
external client takes precedence; a failed operation is never retried through a
different client or store. This is a client bundle, not a Nix installer.
