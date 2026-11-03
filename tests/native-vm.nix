# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  coreSrc,
}:
let
  tool =
    name: version:
    pkgs.runCommand "${name}-${version}"
      {
        pname = name;
        inherit version;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${name}-${version}\n' > $out/bin/${name}
        chmod +x $out/bin/${name}
      '';
  command = "XBPS_ARCH=x86_64 xbps-install -C /dev/null -r /srv/target -i -y -R /tmp/packages";
  install = "xbps-rindex -a /tmp/packages/*.xbps\n${command} native-first native-second";

in
import (coreSrc + "/tests/native-vm.nix") {
  inherit pkgs install;
  name = "xbps";
  tools = [ pkgs.xbps ];
  first = impurifier.makeNativePackages { pkg = tool "native-first" "1"; };
  second = impurifier.makeNativePackages { pkg = tool "native-second" "1"; };
  upgraded = impurifier.makeNativePackages { pkg = tool "native-first" "2"; };
  initialize = "mkdir -p /srv/target/var/db/xbps /srv/target/var/cache/xbps";
  upgrade = "rm -f /tmp/packages/*-repodata; xbps-rindex -a /tmp/packages/*.xbps; ${command} native-first";
  removeFirst = "xbps-remove -C /dev/null -r /srv/target -Ry native-first; xbps-remove -C /dev/null -r /srv/target -oy";
  removeSecond = "xbps-remove -C /dev/null -r /srv/target -Ry native-second";
  verify = "xbps-pkgdb -C /dev/null -r /srv/target -a";
}
