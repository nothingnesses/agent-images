{ pkgs, lib }:

{
  name,
  tag ? "latest",
  agent,
  entrypoint,
  extraPackages ? [],
  extraEnv ? {},
}:

let
  basePackages = with pkgs; [
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

  allPackages = [ agent ] ++ basePackages ++ extraPackages;
in
pkgs.dockerTools.buildLayeredImage {
  inherit name tag;
  contents = allPackages;

  fakeRootCommands = ''
    mkdir -p ./etc ./home/agent ./tmp ./workspace
    cat > ./etc/passwd <<'PASSWD'
    root:x:0:0:root:/root:/bin/bash
    agent:x:1000:1000:agent:/home/agent:/bin/bash
    PASSWD
    cat > ./etc/group <<'GROUP'
    root:x:0:
    agent:x:1000:
    GROUP
    cat > ./etc/nsswitch.conf <<'NSS'
    hosts: files dns
    NSS
    chmod 1777 ./tmp
    chown 1000:1000 ./home/agent ./workspace
  '';

  config = {
    User = "agent";
    WorkingDir = "/workspace";
    Entrypoint = entrypoint;
    Env = [
      "HOME=/home/agent"
      "USER=agent"
      "PATH=${lib.makeBinPath allPackages}"
      "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    ] ++ (lib.mapAttrsToList (k: v: "${k}=${v}") extraEnv);
  };
}
