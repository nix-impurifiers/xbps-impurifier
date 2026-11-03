# SPDX-License-Identifier: MIT
{ pkgs, impurifier }:
let
  source = pkgs.fetchzip {
    url = "https://github.com/void-linux/void-packages/archive/0c95b62a33e6639b5c4045921abe4782476f21a1.tar.gz";
    hash = "sha256-m8JNXU/sP1ufS9RyyGpYfDZt1kQVyEWk//IREZyiI/w=";
  };
  tool =
    version:
    pkgs.runCommand "template-tool-${version}"
      {
        pname = "template-tool";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${version}\n' > $out/bin/template-tool
        chmod +x $out/bin/template-tool
      '';
  app =
    offline: version:
    impurifier.makeXbps {
      pkg = tool version;
      inherit offline;
      hostDependencies = [ ];
      configFiles."/etc/template-tool.conf" = pkgs.writeText "template-tool.conf" "version=${version}\n";
    };
  template =
    offline: version:
    impurifier.makeTemplate {
      package = app offline version;
      sourceUrl = "http://127.0.0.1:8080/${if offline then "offline" else "net"}${version}.xbps";
    };
  provider = impurifier.buildXbps {
    name = "fixture-native-runtime";
    version = "1";
    provides = [
      "nix-1_1"
      "python3-3_1"
    ];
    payload = pkgs.runCommand "template-runtime-provider" { } ''
      mkdir -p $out/usr/bin
      ln -s ${pkgs.nix}/bin/nix-store $out/usr/bin/nix-store
      ln -s ${pkgs.python3}/bin/python3 $out/usr/bin/python3
    '';
  };
in
pkgs.testers.runNixOSTest {
  name = "xbps-impurifier-src-template";
  globalTimeout = 180;
  requiredFeatures = {
    kvm = false;
    devnet = false;
  };
  nodes.machine = { lib, ... }: {
    virtualisation.qemu.package = lib.mkForce pkgs.qemu;
    virtualisation.qemu.forceAccel = false;
    virtualisation.memorySize = 1536;
    virtualisation.useNixStoreImage = true;
    virtualisation.writableStore = true;
    documentation.enable = false;
    environment.systemPackages = with pkgs; [
      xbps
      nix
      python3
      bash
      git
      libarchive
      curl
      wget
      gnumake
      gcc
      pkg-config
      patch
      binutils
      file
      perl
      which
      diffutils
      findutils
      gawk
      gnused
      gnugrep
      gzip
      bzip2
      xz
      zstd
      util-linux
    ];
    nix.settings.substituters = lib.mkForce [ ];
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("cp -r ${source} /build; chmod -R u+w /build; mkdir -p /srv/artifacts /srv/deps /usr/bin /usr/sbin")
    machine.succeed("cp ${app false "1"} /srv/artifacts/net1.xbps; cp ${app true "1"} /srv/artifacts/offline1.xbps; cp ${app true "2"} /srv/artifacts/offline2.xbps; cp ${provider} /srv/deps/${provider.name}; cp ${impurifier.runtimeXbps} /srv/deps/${impurifier.runtimeXbps.name}; xbps-rindex -a /srv/deps/*.xbps")
    machine.succeed("systemd-run --unit=artifact-server --working-directory=/srv/artifacts python3 -m http.server 8080 --bind 127.0.0.1")
    machine.wait_for_open_port(8080)
    machine.succeed("printf 'XBPS_CHROOT_CMD=ethereal\\nXBPS_ALLOW_CHROOT_BREAKOUT=yes\\n' > /build/etc/conf; ln -s / /build/masterdir; echo x86_64 > /.xbps_chroot_init; mkdir -p /usr/bin; ln -s /run/current-system/sw/bin/bash /usr/bin/bash; ln -s /run/current-system/sw/bin/bash /bin/bash; sed -i '1s|.*|#!/usr/bin/bash|' /build/xbps-src")
    build = "systemd-run --pipe --wait --collect --setenv=HOME=/root --setenv=LC_ALL=C --setenv=PATH=/run/current-system/sw/bin:/usr/bin:/bin --setenv=XBPS_ALLOW_CHROOT_BREAKOUT=yes -p RuntimeMaxSec=45s -p TimeoutStopSec=2s ${pkgs.util-linux}/bin/setsid --wait bash /build/xbps-src -N -n -I -f pkg template-tool "
    machine.succeed("mkdir -p /build/srcpkgs/template-tool; cp -r ${template true "1"}/. /build/srcpkgs/template-tool/; git -C /build init -b main; git -C /build -c user.name=Fixture -c user.email=fixture@invalid add srcpkgs/template-tool; git -C /build -c user.name=Fixture -c user.email=fixture@invalid commit -m fixture")
    machine.succeed("for program in /run/current-system/sw/bin/*; do test -e /usr/bin/$(basename $program) || ln -s $program /usr/bin/$(basename $program); done")
    with subtest("native source checksum rejects a damaged artifact"):
        machine.succeed("cp /srv/artifacts/offline1.xbps /source-good; printf broken > /srv/artifacts/offline1.xbps")
        code, output = machine.execute(build + "2>&1")
        assert code != 0 and "checksum" in output.lower() and "timeout" not in output.lower(), output
        machine.succeed("cp /source-good /srv/artifacts/offline1.xbps")
    print(machine.succeed(build))
    machine.succeed("mkdir -p /srv/offline1 /srv/net1 /srv/offline2; cp /build/hostdir/binpkgs/main/template-tool-1_1.x86_64.xbps /srv/offline1/; xbps-rindex -a /srv/offline1/*.xbps")
    machine.succeed("cp -r ${template false "1"}/. /build/srcpkgs/template-tool/")
    print(machine.succeed(build))
    machine.succeed("cp /build/hostdir/binpkgs/main/template-tool-1_1.x86_64.xbps /srv/net1/; xbps-rindex -a /srv/net1/*.xbps")
    machine.succeed("cp -r ${template true "2"}/. /build/srcpkgs/template-tool/")
    print(machine.succeed(build))
    machine.succeed("cp /build/hostdir/binpkgs/main/template-tool-2_1.x86_64.xbps /srv/offline2/; xbps-rindex -a /srv/offline2/*.xbps; systemctl stop dhcpcd; ip link set eth0 down")
    with subtest("native dependency enforcement and net failure"):
        code, output = machine.execute("xbps-install -y -R /srv/offline1 template-tool 2>&1")
        assert code != 0 and "xbps-impurifier" in output, output
        machine.succeed("xbps-install -y -R /srv/deps fixture-native-runtime xbps-impurifier")
        code, output = machine.execute("xbps-install -y -R /srv/net1 template-tool 2>&1")
        assert "nix-profile-engine:" in output, output
        machine.fail("test -e /opt/nix/profile/bin/template-tool")
    machine.succeed("xbps-install -fy -R /srv/offline1 template-tool; test $(/opt/nix/profile/bin/template-tool) = 1; xbps-pkgdb template-tool; echo administrator > /etc/template-tool.conf")
    machine.succeed("xbps-install -y -R /srv/offline2 -u template-tool; test $(/opt/nix/profile/bin/template-tool) = 2; grep administrator /etc/template-tool.conf")
    machine.succeed("su -s /bin/sh nobody -c /opt/nix/profile/bin/template-tool | grep '^2$'; /usr/sbin/nix-profile-engine prune --keep 0; nix-store --gc; test $(/opt/nix/profile/bin/template-tool) = 2")
    machine.succeed("xbps-remove -y template-tool")
    machine.fail("test -e /opt/nix/profile/bin/template-tool")
    machine.succeed("/usr/sbin/nix-profile-engine prune --keep 0; xbps-remove -y xbps-impurifier; nix-store --gc")
    machine.fail("test -e ${builtins.unsafeDiscardStringContext (toString (tool "2"))}")
  '';
}
