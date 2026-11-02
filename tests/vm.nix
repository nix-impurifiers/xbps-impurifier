# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  hardwareFixture,
}:
let
  tool =
    version:
    pkgs.runCommand "xbps-tool-${version}"
      {
        pname = "xbps-tool";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${version}\n' > $out/bin/xbps-tool
        chmod +x $out/bin/xbps-tool
      '';
  app =
    offline: version:
    impurifier.makeXbps {
      pkg = tool version;
      inherit offline;
      configFiles."/etc/xbps-tool.conf" = pkgs.writeText "xbps-config" "version=${version}\n";
    };
  daemon =
    version:
    pkgs.runCommand "xbps-service-${version}"
      {
        pname = "xbps-service";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        cat > $out/bin/xbps-service <<'SCRIPT'
        #!${pkgs.busybox}/bin/sh
        echo ${version} > /var/lib/xbps-service/version
        exec ${pkgs.busybox}/bin/sleep infinity
        SCRIPT
        chmod +x $out/bin/xbps-service
      '';
  service =
    version:
    impurifier.makeOfflineXbps {
      pkg = daemon version;
      users.xbps-service = { };
      directories."/var/lib/xbps-service" = {
        owner = "xbps-service:xbps-service";
        mode = "0750";
      };
      lifecycle = {
        onInstall = ''
          /usr/bin/python3 -c "import pwd; pwd.getpwnam('xbps-service')"
          test -x /opt/nix/profile/bin/xbps-service
          echo initialized > /var/lib/xbps-service/initialized
        '';
        onUpgrade = "echo ${version} > /var/lib/xbps-service/migrated";
      };
      runit.run = pkgs.writeText "xbps-service.run" ''
        #!/bin/sh
        exec chpst -u xbps-service:xbps-service /opt/nix/profile/bin/xbps-service
      '';
    };
  passive = impurifier.makeOfflineXbps {
    pkg = daemon "1";
    name = "passive-service";
    runit = {
      startOnInstall = false;
      run = pkgs.writeText "passive-service.run" ''
        #!/bin/sh
        exec ${pkgs.busybox}/bin/sleep infinity
      '';
    };
  };
  provider = impurifier.buildXbps {
    name = "vm-runtime";
    version = "1";
    provides = [
      "nix-1_1"
      "python3-1_1"
      "runit-1_1"
      "busybox-1_1"
    ];
    payload = pkgs.runCommand "opkg-runtime-provider" { } ''
      mkdir -p $out/usr/share/impurifier-vm
      echo preinstalled > $out/usr/share/impurifier-vm/runtime
    '';
  };
  hostDriver =
    version:
    impurifier.buildXbps {
      name = "impurifier-host-driver";
      inherit version;
      architecture = "x86_64";
      payload = hardwareFixture.driver version;
      installScript = pkgs.writeText "cooperating-native-driver-INSTALL" ''
        #!/bin/sh
        case "$1" in post) /usr/sbin/nix-profile-engine reconcile ;; esac
      '';
    };
  hardware = impurifier.makeOfflineXbps {
    hostDependencies = [ "impurifier-host-driver>=0" ];
    pkg = hardwareFixture.tool;
    inherit (hardwareFixture) hardware;
  };
  repository = packages: impurifier.makeRepository { inherit packages; };
in
pkgs.testers.runNixOSTest {
  name = "xbps-impurifier";
  requiredFeatures = {
    kvm = false;
    devnet = false;
  };
  nodes.machine = { lib, ... }: {
    virtualisation.memorySize = 2048;
    virtualisation.useNixStoreImage = true;
    virtualisation.writableStore = true;
    virtualisation.qemu.package = lib.mkForce pkgs.qemu;
    virtualisation.qemu.forceAccel = false;
    environment.systemPackages = [
      pkgs.xbps
      pkgs.runit
      pkgs.busybox
      pkgs.nix
      pkgs.python3
    ];
    systemd.services.runit-fixture = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = "${pkgs.runit}/bin/runsvdir -P /var/service";
      path = [
        pkgs.runit
        pkgs.busybox
      ];
    };
    systemd.tmpfiles.rules = [
      "d /var/service 0755 root root -"
      "L+ /usr/bin/sv - - - - ${pkgs.runit}/bin/sv"
      "L+ /usr/bin/chpst - - - - ${pkgs.runit}/bin/chpst"
      "L+ /usr/bin/busybox - - - - ${pkgs.busybox}/bin/busybox"
      "L+ /usr/bin/mkdir - - - - ${pkgs.coreutils}/bin/mkdir"
      "L+ /usr/bin/chown - - - - ${pkgs.coreutils}/bin/chown"
      "L+ /usr/bin/chmod - - - - ${pkgs.coreutils}/bin/chmod"
      "d /usr/bin 0755 root root -"
      "L+ /usr/bin/python3 - - - - ${pkgs.python3}/bin/python3"
      "L+ /usr/bin/nix-store - - - - ${pkgs.nix}/bin/nix-store"
      "L+ /usr/bin/systemctl - - - - ${pkgs.systemd}/bin/systemctl"
      "L+ /usr/bin/systemd-sysusers - - - - ${pkgs.systemd}/bin/systemd-sysusers"
      "L+ /usr/bin/systemd-tmpfiles - - - - ${pkgs.systemd}/bin/systemd-tmpfiles"
    ];
    nix.settings.substituters = lib.mkForce [ ];
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /tmp/packages /var/db/xbps /var/cache/xbps")
    machine.succeed("cp -rL /etc/systemd/system /tmp/systemd-system; chmod -R u+w /tmp/systemd-system; rm /etc/systemd/system; mv /tmp/systemd-system /etc/systemd/system; systemctl daemon-reload")
    machine.succeed("systemctl stop dhcpcd; ip link set eth0 down")
    xbps = "XBPS_ARCH=x86_64 xbps-install -C /dev/null -i -y -f "
    def install(repo, names):
        return machine.succeed(xbps + "-R " + repo + " " + names)
    install("${
      repository [
        provider
        impurifier.runtimeXbps
      ]
    }", "vm-runtime xbps-impurifier")
    machine.fail("test -e ${builtins.unsafeDiscardStringContext (toString (tool "1"))}")
    with subtest("native post-install failure preserves the previous profile"):
        before = machine.succeed("readlink /opt/nix/profile").strip()
        code, output = machine.execute(xbps + "-R ${repository [ (app false "1") ]} xbps-tool 2>&1")
        assert "nix-profile-engine:" in output, output
        assert machine.succeed("readlink /opt/nix/profile").strip() == before
    with subtest("offline repository reinstall recovers without a network"):
        install("${repository [ (app true "1") ]}", "xbps-tool")
        machine.succeed("test $(/opt/nix/profile/bin/xbps-tool) = 1")
    with subtest("native configuration protection survives transport switches and upgrades"):
        machine.succeed("echo local > /etc/xbps-tool.conf")
        install("${repository [ (app false "1") ]}", "xbps-tool")
        machine.succeed("grep local /etc/xbps-tool.conf")
        install("${repository [ (app true "2") ]}", "xbps-tool")
        machine.succeed("grep local /etc/xbps-tool.conf; test $(/opt/nix/profile/bin/xbps-tool) = 2")
    with subtest("one effective activation after native transaction unpacking"):
        output = install("${
          repository [
            (impurifier.makeOfflineXbps {
              pkg = pkgs.hello;
              name = "batch-a";
              version = "1";
            })
            (impurifier.makeOfflineXbps {
              pkg = pkgs.hello;
              name = "batch-b";
              version = "1";
            })
          ]
        }", "batch-a batch-b")
        assert output.count("activated ") == 1, output
        machine.succeed("/opt/nix/profile/bin/hello | grep Hello")
        machine.succeed("xbps-remove -y batch-a batch-b")
    with subtest("service ownership, lifecycle and administrator intent"):
        install("${repository [ (service "1") ]}", "xbps-service")
        machine.wait_until_succeeds("sv status /var/service/xbps-service | grep '^run:'")
        machine.wait_until_succeeds("grep '^1$' /var/lib/xbps-service/version")
        machine.succeed("grep initialized /var/lib/xbps-service/initialized; test $(stat -c %U /var/lib/xbps-service) = xbps-service")
        install("${repository [ (service "2") ]}", "xbps-service")
        machine.wait_until_succeeds("grep '^2$' /var/lib/xbps-service/version")
        machine.succeed("grep '^2$' /var/lib/xbps-service/migrated")
        machine.succeed("sv down /var/service/xbps-service; rm /var/service/xbps-service")
        install("${repository [ (service "1") ]}", "xbps-service")
        machine.fail("sv status /etc/sv/xbps-service | grep '^run:'")
        machine.fail("test -L /var/service/xbps-service")
        machine.succeed("ln -s /etc/sv/xbps-service /var/service/xbps-service")
        machine.wait_until_succeeds("sv up /var/service/xbps-service")
        machine.succeed("xbps-remove -y xbps-service")
        machine.fail("sv status /etc/sv/xbps-service | grep '^run:'")
    with subtest("runit enable retry preserves an initially stopped service"):
        machine.succeed("systemctl stop runit-fixture; mkdir -p /etc/sv/passive-service/supervise; mkfifo /etc/sv/passive-service/supervise/ok")
        code, output = machine.execute(xbps + "-R ${repository [ passive ]} passive-service 2>&1")
        assert "runit supervisor did not attach" in output, output
        machine.succeed("grep 'pending enable' /etc/sv/passive-service/down")
        machine.succeed("systemctl start runit-fixture")
        install("${repository [ passive ]}", "passive-service")
        machine.succeed("sv status /var/service/passive-service | grep '^down:'; test ! -e /etc/sv/passive-service/down")
        machine.succeed("sv up /var/service/passive-service; xbps-remove -y passive-service")
        machine.fail("sv status /etc/sv/passive-service | grep '^run:'")
    with subtest("cooperating native driver upgrades refresh snapshots"):
        code, output = machine.execute(xbps + "-R ${repository [ hardware ]} hardware-tool 2>&1")
        assert code != 0 and "impurifier-host-driver" in output, output
        install("${
          repository [
            (hostDriver "1")
            hardware
          ]
        }", "impurifier-host-driver hardware-tool")
        machine.succeed("/opt/nix/profile/bin/hardware-tool | grep '^1$'")
        install("${repository [ (hostDriver "2") ]}", "impurifier-host-driver")
        machine.succeed("/opt/nix/profile/bin/hardware-tool | grep '^2$'")
        machine.succeed("xbps-remove -y hardware-tool impurifier-host-driver")
    with subtest("GC and native removal release profile intent"):
        machine.succeed("nix-store --gc; test $(/opt/nix/profile/bin/xbps-tool) = 2")
        machine.succeed("xbps-remove -y xbps-tool")
        machine.fail("test -e /opt/nix/profile/bin/xbps-tool")
        machine.succeed("grep local /etc/xbps-tool.conf")
        machine.succeed("/usr/sbin/nix-profile-engine prune --keep 0; nix-store --gc; test -d /opt/nix/profile")
  '';
}
