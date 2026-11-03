# SPDX-License-Identifier: MIT
{ ... }:
{ lib, inputs, ... }:
{
  flake.lib = lib.mkForce {
    xbps-impurifier =
      { pkgs }:
      import ../../../nix {
        inherit pkgs;
        coreSrc = inputs.impurifier;
        sourceInfo = inputs.self;
      };
  };
  perSystem =
    { pkgs, ... }:
    let
      impurifier = import ../../../nix {
        inherit pkgs;
        coreSrc = inputs.impurifier;
        sourceInfo = inputs.self;
      };
    in
    {
      packages = {
        default = impurifier.engine;
        engine = impurifier.engine;
        runtime-xbps = impurifier.runtimeXbps;
        hello-net-xbps = impurifier.makeNetXbps { pkg = pkgs.hello; };
        hello-offline-xbps = impurifier.makeOfflineXbps { pkg = pkgs.hello; };
      };
      formatter = pkgs.nixfmt-tree;
      checks =
        (import ../../../tests {
          inherit pkgs impurifier;
          coreSrc = inputs.impurifier;
        })
        // {
          bundled-vm = import ../../../tests/vm.nix {
            inherit pkgs;
            hardwareFixture = import (inputs.impurifier + "/tests/hardware-fixture.nix") { inherit pkgs; };
            bundled = true;
            impurifier = impurifier // {
              runtimeXbps = impurifier.makeRuntimeXbps {
                bundledNixStore = "${
                  import (inputs.impurifier + "/tests/static-nix.nix") { inherit pkgs; }
                }/bin/nix-store";
                bundledNixNotices = [ "${pkgs.nix.src}/COPYING" ];
              };
            };
          };
        };
    };
}
