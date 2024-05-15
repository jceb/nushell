# Documentation: https://nixos.wiki/wiki/Flakes
# Documentation: https://yuanwang.ca/posts/getting-started-with-flakes.html
{
  description = "NixOS docker image";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, nixpkgs-unstable, flake-utils, }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        unstable = nixpkgs-unstable.legacyPackages.${system};
        nushell_pkg = unstable.nushell;
        package = pkgs.lib.importJSON ./package.json;
        pkgVersionsEqual = x: y:
          let
            attempt = builtins.tryEval
              (assert builtins.substring 0 (builtins.stringLength x) y == x; y);
          in
          if attempt.success then
            attempt.value
          else
          # Version can be bumped in the prerelease or build version to create a
          # custom local revision, see https://semver.org/
            abort "Version mismatch: ${y} doesn't start with ${x}";
        version = pkgVersionsEqual "${nushell_pkg.version}" package.version;
      in
      with pkgs; rec {
        # Development environment: nix develop
        devShells.default = mkShell {
          name = package.name;
          nativeBuildInputs = [
            deno
            gh
            git-cliff
            just
            # nodePackages.semver
            nushell_pkg
            skopeo
          ];
        };

        packages.docker = pkgs.dockerTools.streamLayeredImage {
          # Documentation: https://ryantm.github.io/nixpkgs/builders/images/dockertools/
          name = "${package.registry}/${package.name}";
          tag = version;
          # created = "now";
          # author = "not yet supported";
          maxLayers = 125;
          contents = with pkgs.dockerTools; [
            # usrBinEnv
            binSh
            caCertificates
            fakeNss
            # busybox
            # nix
            # coreutils
            # gnutar
            # gzip
            # gnugrep
            # which
            # curl
            # less
            # findutils
            nushell_pkg
            # entrypoint
          ];
          enableFakechroot = true;
          fakeRootCommands = ''
            set -exuo pipefail
            mkdir -p /run/kanidmd
            chown 65534:65534 /run/kanidmd
            # mkdir /tmp
            # chmod 1777 /tmp
          '';
          config = {
            # Valid values, see: https://github.com/moby/docker-image-spec
            # and https://oci-playground.github.io/specs-latest/
            "ExposedPorts" = {
              "8443/tcp" = { };
              "3636/tcp" = { };
            };
            # Entrypoint = [];
            Cmd = [
              "${nushell_pkg}/bin/nu"
              "-n"
            ];
            # Env = ["VARNAME=xxx"];
            WorkingDir = "/";
            # User 'nobody' and group 'nogroup'
            # User = "65534";
            # Group = "65534";
            Labels = {
              # Well-known annotations: https://github.com/opencontainers/image-spec/blob/main/annotations.md
              "org.opencontainers.image.authors" =
                builtins.elemAt package.contributors 0;
              "org.opencontainers.image.vendor" = package.author;
              "org.opencontainers.image.description" = package.description;
              "org.opencontainers.image.source" = package.repository.url;
              "org.opencontainers.image.url" = package.homepage;
              "org.opencontainers.image.licenses" = package.license;
              "org.opencontainers.image.base.name" =
                "${package.repository.url}/${package.name}:${package.version}";
              "org.opencontainers.image.version" = package.version;
              "org.opencontainers.image.ref.name" = package.name;
            };
          };
        };

        # The default package when a specific package name isn't specified: nix build
        packages.default = packages.docker;
      });
}
