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
  withNix ? false,
  nixPackage ? pkgs.nix,
  nixExperimentalFeatures ? [
    "nix-command"
    "flakes"
  ],
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
  allPackages = [ agent ] ++ basePackages ++ extraPackages ++ nixDeps;

  home = "/home/${user}";
  uidStr = toString uid;
  gidStr = toString gid;

  nixFakeRootCommands = lib.optionalString withNix ''
    chown -R ${uidStr}:${gidStr} ./nix
  '';

  nixEnvVars = lib.optionals withNix [
    "NIX_CONF_DIR=/etc/nix"
    "NIX_PATH=nixpkgs=${pkgs.path}"
  ];
in
pkgs.dockerTools.buildLayeredImage {
  meta = agent.meta or { };
  inherit name tag;
  contents = allPackages;
  includeNixDB = withNix;

  fakeRootCommands = ''
    mkdir -p ./etc .${home} ./tmp .${workingDir}
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
    chown ${uidStr}:${gidStr} .${home} .${workingDir}
  ''
  + nixFakeRootCommands;

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
    ++ nixEnvVars
    ++ (lib.mapAttrsToList (k: v: "${k}=${v}") extraEnv);
  };
}
