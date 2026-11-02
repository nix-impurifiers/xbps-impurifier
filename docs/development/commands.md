# Commands

```sh
nix flake check -L
nix fmt
nix build '.#runtime-xbps' '.#hello-net-xbps' '.#hello-offline-xbps'
```

Local shared-core development can add
`--override-input impurifier path:../impurifier --no-write-lock-file`.
Use workspace flake-sync to converge published pins; do not commit path inputs.
