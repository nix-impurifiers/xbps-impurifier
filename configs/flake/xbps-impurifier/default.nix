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
      };
  };
  perSystem =
    { pkgs, ... }:
    let
      impurifier = import ../../../nix {
        inherit pkgs;
        coreSrc = inputs.impurifier;
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
      checks = import ../../../tests {
        inherit pkgs impurifier;
        coreSrc = inputs.impurifier;
      };
    };
}
