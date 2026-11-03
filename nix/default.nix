# SPDX-License-Identifier: MIT
{
  pkgs,
  coreSrc,
  sourceInfo ? { },
}:
let
  inherit (pkgs) lib;
  core = import (coreSrc + "/nix") {
    inherit pkgs;
    namespace = "xbps-impurifier";
    sourceInfo = {
      # Native updates must include adapter-only releases, not just engine pins.
      lastModified = pkgs.lib.max (if builtins.isAttrs coreSrc then coreSrc.lastModified or 0 else 0) (
        if builtins.isAttrs sourceInfo then sourceInfo.lastModified or 0 else 0
      );
    };
  };
  architecture =
    if pkgs.stdenv.hostPlatform.isx86_64 then
      "x86_64"
    else if pkgs.stdenv.hostPlatform.isAarch64 then
      "aarch64"
    else
      throw "unsupported XBPS target architecture";
  atom = value: builtins.match "[A-Za-z0-9_.+<>=*?~-]+" value != null;
  buildXbps =
    {
      name,
      version,
      revision ? "1",
      architecture ? "noarch",
      payload,
      description ? "Impurified Nix application",
      license ? "LicenseRef-Unknown",
      dependencies ? [ ],
      provides ? [ ],
      conflicts ? [ ],
      replaces ? [ ],
      configPaths ? [ ],
      installScript ? null,
      removeScript ? null,
    }:
    assert lib.assertMsg (
      builtins.match "[a-z0-9][a-z0-9+.-]+" name != null
    ) "invalid XBPS package name";
    assert lib.assertMsg (
      builtins.match "[0-9][A-Za-z0-9.+~]*" version != null && builtins.match "[0-9]+" revision != null
    ) "invalid XBPS version/revision";
    assert lib.assertMsg (
      builtins.match "[A-Za-z0-9_.+-]+" architecture != null
      && builtins.match "[^\n\r]+" description != null
      && builtins.stringLength description <= 80
    ) "invalid XBPS architecture or description";
    assert lib.assertMsg (lib.all atom (
      dependencies ++ provides ++ conflicts ++ replaces
    )) "invalid XBPS dependency";
    pkgs.runCommand "${name}-${version}_${revision}.${architecture}.xbps"
      {
        nativeBuildInputs = [ pkgs.xbps ];
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
      }
      ''
        mkdir root packages
        cp -r ${payload}/. root/
        chmod -R u+w root
        ${lib.optionalString (
          installScript != null
        ) "install -m755 ${lib.escapeShellArg (toString installScript)} root/INSTALL"}
        ${lib.optionalString (
          removeScript != null
        ) "install -m755 ${lib.escapeShellArg (toString removeScript)} root/REMOVE"}
        cd packages
        xbps-create -A ${lib.escapeShellArg architecture} -n ${lib.escapeShellArg "${name}-${version}_${revision}"} \
          -s ${lib.escapeShellArg description} -l ${lib.escapeShellArg license} \
          ${
            lib.optionalString (
              dependencies != [ ]
            ) "-D ${lib.escapeShellArg (lib.concatStringsSep " " dependencies)}"
          } \
          ${
            lib.optionalString (provides != [ ]) "-P ${lib.escapeShellArg (lib.concatStringsSep " " provides)}"
          } \
          ${
            lib.optionalString (
              conflicts != [ ]
            ) "-C ${lib.escapeShellArg (lib.concatStringsSep " " conflicts)}"
          } \
          ${
            lib.optionalString (replaces != [ ]) "-R ${lib.escapeShellArg (lib.concatStringsSep " " replaces)}"
          } \
          ${
            lib.optionalString (
              configPaths != [ ]
            ) "-F ${lib.escapeShellArg (lib.concatStringsSep " " configPaths)}"
          } \
          ../root
        cp *.xbps "$out"
      '';
  makeNativePackages =
    args:
    let
      trees = core.makeNativeTrees args;
    in
    pkgs.runCommand "native-owned-xbps-collection"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.xbps
        ];
      }
      ''
        python3 ${./native-xbps.py} ${trees} "$out" ${architecture}
      '';
  installScript = pkgs.writeText "xbps-impurifier-INSTALL" ''
    #!/bin/sh
    set -eu
    case "$1" in post) /usr/sbin/nix-profile-engine reconcile ;; esac
  '';
  removeScript = pkgs.writeText "xbps-impurifier-REMOVE" ''
    #!/bin/sh
    set -eu
    case "$1" in post) /usr/sbin/nix-profile-engine reconcile ;; esac
  '';
  makeXbps =
    args@{
      pkg,
      revision ? "1",
      hostDependencies ? null,
      ...
    }:
    let
      hostBackend =
        args.hostBackend or (
          if (args.systemd or null) != null then
            "systemd"
          else if (args.openrc or null) != null then
            "openrc"
          else
            "runit"
        );
      hostDeps =
        if hostDependencies != null then
          hostDependencies
        else if hostBackend == "runit" then
          [
            "runit>=0"
            "busybox>=0"
          ]
        else if hostBackend == "openrc" then
          [
            "openrc>=0"
            "busybox>=0"
          ]
        else
          [ "systemd>=0" ];
      payload = core.makePayload (
        (builtins.removeAttrs args [
          "revision"
          "hostDependencies"
        ])
        // {
          inherit hostBackend;
        }
      );
    in
    buildXbps {
      name = payload.name;
      inherit (payload) version description configPaths;
      inherit
        payload
        revision
        architecture
        installScript
        removeScript
        ;
      dependencies = [
        "xbps-impurifier>=${core.runtimeVersion}_1"
      ]
      ++ lib.optionals (payload.hostEnabled || (args.hostDependencies or null) != null) hostDeps;
    };
  makeRuntimeXbps =
    {
      bundledNixStore ? null,
      bundledNixNotices ? [ ],
      nixDependency ? (if bundledNixStore == null then "nix>=0" else null),
      pythonDependency ? "python3>=0",
    }:
    buildXbps {
      name = "xbps-impurifier";
      version = core.runtimeVersion;
      payload = core.makeRuntimeTree { inherit bundledNixStore bundledNixNotices; };
      architecture = if bundledNixStore == null then "noarch" else architecture;
      license = "MIT";
      dependencies = lib.optional (nixDependency != null) nixDependency ++ [ pythonDependency ];
      inherit installScript;
    };
  makeTemplate =
    { package, sourceUrl }:
    assert lib.assertMsg (
      builtins.isString sourceUrl
      && (lib.hasPrefix "https://" sourceUrl || lib.hasPrefix "http://" sourceUrl)
      && !(lib.hasInfix "\n" sourceUrl)
      && !(lib.hasInfix "\r" sourceUrl)
      && !(lib.hasInfix ">" sourceUrl)
    ) "sourceUrl must be an HTTP(S) artifact URL";
    pkgs.runCommand "impurifier-xbps-template"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.libarchive
        ];
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
        options = pkgs.writeText "template-options.json" (builtins.toJSON { inherit sourceUrl; });
      }
      ''
        python3 ${./template.py} ${package} "$options" "$out"
      '';
  makeRepository =
    {
      packages,
      name ? "impurifier-xbps-repository",
    }:
    assert lib.assertMsg (packages != [ ]) "XBPS repository requires packages";
    pkgs.runCommand name { nativeBuildInputs = [ pkgs.xbps ]; } ''
      mkdir -p $out
      ${lib.concatMapStringsSep "\n" (package: ''
        destination="$out/${package.name or (builtins.baseNameOf (toString package))}"
        test ! -e "$destination" || { echo 'duplicate XBPS repository filename' >&2; exit 1; }
        cp ${package} "$destination"
      '') packages}
      xbps-rindex -a $out/*.xbps
    '';
in
{
  inherit (core)
    engine
    offlineCache
    unit
    runtimeVersion
    ;
  inherit
    buildXbps
    makeNativePackages
    makeXbps
    makeRuntimeXbps
    makeRepository
    makeTemplate
    ;
  runtimeXbps = makeRuntimeXbps { };
  makeNetXbps = args: makeXbps (args // { offline = false; });
  makeOfflineXbps = args: makeXbps (args // { offline = true; });
  makePackage = args: {
    net = makeXbps (args // { offline = false; });
    offline = makeXbps (args // { offline = true; });
  };
}
