# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  coreSrc,
}:
let
  net = impurifier.makeNetXbps { pkg = pkgs.hello; };
  offline = impurifier.makeOfflineXbps { pkg = pkgs.hello; };
  closure = pkgs.closureInfo {
    rootPaths = [
      net
      offline
    ];
  };
  repository = impurifier.makeRepository {
    packages = [
      net
      (impurifier.makeRuntimeXbps { nixDependency = "custom-nix>=0"; })
    ];
  };
in
{
  template-vm = import ./template-vm.nix { inherit pkgs impurifier; };
  unit = impurifier.unit;
  emitter = pkgs.runCommand "xbps-impurifier-contract" { nativeBuildInputs = [ pkgs.xbps ]; } ''
    XBPS_ARCH=x86_64 xbps-query -C /dev/null -R --repository=${repository} -p pkgver hello | grep '^hello-2.12.3_1$'
    XBPS_ARCH=x86_64 xbps-query -C /dev/null -R --repository=${repository} -p run_depends xbps-impurifier | grep 'custom-nix>=0'
    test "$(wc -l < ${closure}/store-paths)" = 2
    touch $out
  '';
  vm = import ./vm.nix {
    inherit pkgs impurifier;
    hardwareFixture = import (coreSrc + "/tests/hardware-fixture.nix") { inherit pkgs; };
  };
}
