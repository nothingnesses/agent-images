{ pkgs, lib }:

let
  defaultBasePackages = with pkgs; [
    bashInteractive
    coreutils
    findutils
    gnugrep
    gawk
    git
    ripgrep
    less
    curl
    cacert
    gnused
    diffutils
    jq
    gnutar
    gzip
    which
  ];

  # Keep in sync with nixpkgs (nixos/modules/programs/nix-ld.nix).
  # Last synced: 2026-04-06, nixpkgs commit e4bae1bd10c9.
  defaultNixLdLibraries = with pkgs; [
    zlib
    zstd
    stdenv.cc.cc
    curl
    openssl
    attr
    libssh
    bzip2
    libxml2
    acl
    libsodium
    util-linux
    xz
    systemd # heavyweight; users who need smaller images can override nixLdLibraries
  ];
in

{
  name,
  tag ? "latest",
  agent,
  entrypoint,
  user ? "agent",
  uid ? 1000,
  gid ? uid,
  workingDir ? "/workspace",
  basePackages ? defaultBasePackages,
  extraPackages ? [ ],
  extraEnv ? { },
  extraDirectories ? [ ],
  withNix ? false,
  nixPackage ? pkgs.nix,
  nixExperimentalFeatures ? [
    "nix-command"
    "flakes"
  ],
  withNixLd ? false,
  nixLdLibraries ? defaultNixLdLibraries,
  extraNixLdLibraries ? [ ],
}:

let
  nixConf = pkgs.writeTextDir "etc/nix/nix.conf" ''
    sandbox = false
    experimental-features = ${lib.concatStringsSep " " nixExperimentalFeatures}
  '';

  nixDeps = lib.optionals withNix [
    nixPackage
    nixConf
  ];

  # These bindings are only demanded transitively through nixLdFakeRootCommands,
  # nixLdDeps, and nixLdEnvVars, all of which short-circuit to empty values when
  # withNixLd = false. Nix never evaluates the right-hand side of a let binding
  # that is not demanded, so pkgs.nix-ld is not fetched/built when the feature
  # is disabled. This is safe but fragile: any future code that references these
  # bindings outside a withNixLd gate would silently force pkgs.nix-ld.
  nixLdLinkPath = lib.removeSuffix "\n" (builtins.readFile "${pkgs.nix-ld}/nix-support/ldpath");
  nixLdLinkDir = builtins.dirOf nixLdLinkPath;
  nixLdTarget = "${pkgs.nix-ld}/libexec/nix-ld";
  nixLdRealLinker = pkgs.stdenv.cc.bintools.dynamicLinker;
  allNixLdLibraries = nixLdLibraries ++ extraNixLdLibraries;
  # The library store paths enter the image via Nix's string context tracking:
  # lib.makeLibraryPath produces strings carrying references to each library's
  # store path, and buildLayeredImage includes all store paths referenced by
  # config.Env strings in the image closure. The libraries do not need to be
  # added to contents/allPackages explicitly.
  nixLdLibraryPath = lib.makeLibraryPath (map lib.getLib allNixLdLibraries);
  nixLdDeps = lib.optionals withNixLd [ pkgs.nix-ld ];

  allPackages = [ agent ] ++ basePackages ++ extraPackages ++ nixDeps ++ nixLdDeps;

  home = "/home/${user}";
  uidStr = toString uid;
  gidStr = toString gid;

  normalizeOwnedDirectory =
    dir:
    if dir == "~" then
      home
    else if lib.hasPrefix "~/" dir then
      "${home}/${lib.removePrefix "~/" dir}"
    else
      dir;

  defaultOwnedDirectories = [
    home
    "${home}/.config"
    "${home}/.cache"
    "${home}/.local"
    "${home}/.local/share"
    "${home}/.local/state"
    workingDir
  ];
  ownedDirectories = lib.unique (
    defaultOwnedDirectories ++ map normalizeOwnedDirectory extraDirectories
  );
  ownedDirectoryArgs = lib.concatMapStringsSep " " (
    dir: lib.escapeShellArg ".${dir}"
  ) ownedDirectories;

  xdgEnvPairs = {
    XDG_CONFIG_HOME = "${home}/.config";
    XDG_CACHE_HOME = "${home}/.cache";
    XDG_DATA_HOME = "${home}/.local/share";
    XDG_STATE_HOME = "${home}/.local/state";
  };

  # Filter out any XDG vars that the user overrides via extraEnv,
  # avoiding duplicate env var names (undefined behavior per OCI spec).
  xdgEnvVars = lib.mapAttrsToList (k: v: "${k}=${v}") (
    lib.filterAttrs (k: _: !(lib.hasAttr k extraEnv)) xdgEnvPairs
  );

  deniedPrefixes = [
    "/etc"
    "/bin"
    "/usr"
    "/lib"
    "/sbin"
    "/dev"
    "/proc"
    "/sys"
    "/run"
    "/tmp"
    "/nix"
    "/var"
    "/root"
  ];

  nixFakeRootCommands = lib.optionalString withNix ''
    chown -R ${uidStr}:${gidStr} ./nix
  '';

  nixLdFakeRootCommands = lib.optionalString withNixLd ''
    mkdir -p ${lib.escapeShellArg ".${nixLdLinkDir}"}
    ln -s ${lib.escapeShellArg nixLdTarget} ${lib.escapeShellArg ".${nixLdLinkPath}"}
  '';

  nixEnvVars = lib.optionals withNix [
    "NIX_CONF_DIR=/etc/nix"
    "NIX_PATH=nixpkgs=${pkgs.path}"
  ];

  nixLdEnvPairs = {
    NIX_LD = nixLdRealLinker;
    NIX_LD_LIBRARY_PATH = nixLdLibraryPath;
  };

  # Filter out any nix-ld vars that the user overrides via extraEnv,
  # avoiding duplicate env var names (matching the xdgEnvVars pattern).
  nixLdEnvVars = lib.optionals withNixLd (
    lib.mapAttrsToList (k: v: "${k}=${v}") (
      lib.filterAttrs (k: _: !(lib.hasAttr k extraEnv)) nixLdEnvPairs
    )
  );
in
assert lib.assertMsg (lib.all (d: lib.hasPrefix "/" d)
  ownedDirectories
) "mkAgentImage: extraDirectories entries must be absolute container paths or use ~/...";
assert lib.assertMsg
  (lib.all (d: !(lib.any (p: d == p || lib.hasPrefix (p + "/") d) deniedPrefixes)) ownedDirectories)
  "mkAgentImage: extraDirectories must not include system paths (${lib.concatStringsSep ", " deniedPrefixes})";
assert lib.assertMsg (lib.all (d: builtins.match "[a-zA-Z0-9/_.+@-]+" d != null) ownedDirectories)
  "mkAgentImage: extraDirectories paths may only contain alphanumeric characters, /, _, ., +, @, and -";
assert lib.assertMsg (lib.all (
  d: builtins.match ".*\\.\\." d == null
) ownedDirectories) "mkAgentImage: extraDirectories paths must not contain '..' components";
pkgs.dockerTools.buildLayeredImage {
  meta = agent.meta or { };
  inherit name tag;
  contents = allPackages;
  includeNixDB = withNix;

  fakeRootCommands = ''
    mkdir -p ./etc ./tmp ${ownedDirectoryArgs}
    cat > ./etc/passwd <<'PASSWD'
    root:x:0:0:root:/root:/bin/bash
    ${user}:x:${uidStr}:${gidStr}:${user}:${home}:/bin/bash
    PASSWD
    cat > ./etc/group <<'GROUP'
    root:x:0:
    ${user}:x:${gidStr}:
    GROUP
    cat > ./etc/nsswitch.conf <<'NSS'
    hosts: files dns
    NSS
    chmod 1777 ./tmp
    chown ${uidStr}:${gidStr} ${ownedDirectoryArgs}
  ''
  + nixFakeRootCommands
  + nixLdFakeRootCommands;

  config = {
    User = user;
    WorkingDir = workingDir;
    Entrypoint = entrypoint;
    Env = [
      "HOME=${home}"
      "USER=${user}"
      "PATH=${lib.makeBinPath allPackages}"
      "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    ]
    ++ xdgEnvVars
    ++ nixEnvVars
    ++ nixLdEnvVars
    ++ (lib.mapAttrsToList (k: v: "${k}=${v}") extraEnv);
  };
}
