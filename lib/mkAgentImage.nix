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
  ];
in

{
  name,
  tag ? "latest",
  agent,
  entrypoint,
  user ? "agent",
  uid ? 1000,
  workingDir ? "/workspace",
  basePackages ? defaultBasePackages,
  extraPackages ? [],
  extraEnv ? {},
}:

let
  allPackages = [ agent ] ++ basePackages ++ extraPackages;
  home = "/home/${user}";
in
pkgs.dockerTools.buildLayeredImage {
  meta = agent.meta or {};
  inherit name tag;
  contents = allPackages;

  fakeRootCommands = ''
    mkdir -p ./etc .${home} ./tmp .${workingDir}
    cat > ./etc/passwd <<'PASSWD'
    root:x:0:0:root:/root:/bin/bash
    ${user}:x:${toString uid}:${toString uid}:${user}:${home}:/bin/bash
    PASSWD
    cat > ./etc/group <<'GROUP'
    root:x:0:
    ${user}:x:${toString uid}:
    GROUP
    cat > ./etc/nsswitch.conf <<'NSS'
    hosts: files dns
    NSS
    chmod 1777 ./tmp
    chown ${toString uid}:${toString uid} .${home} .${workingDir}
  '';

  config = {
    User = user;
    WorkingDir = workingDir;
    Entrypoint = entrypoint;
    Env = [
      "HOME=${home}"
      "USER=${user}"
      "PATH=${lib.makeBinPath allPackages}"
      "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    ] ++ (lib.mapAttrsToList (k: v: "${k}=${v}") extraEnv);
  };
}
