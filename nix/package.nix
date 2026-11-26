# Nix package for the LubimyCzytaj Audiobookshelf metadata provider.
#
# The upstream Dockerfile bundles server.js with esbuild only to shrink the
# image; running `node server.js` with the dependency tree does exactly the
# same work, so the bundling step is skipped here.
{
  lib,
  buildNpmPackage,
  makeWrapper,
  nodejs,
}:

buildNpmPackage rec {
  pname = "lubimyczytac-abs";
  # package.json is the single source of truth for the version.
  version = (lib.importJSON ../package.json).version;

  src = lib.cleanSourceWith {
    src = ../.;
    filter =
      path: _type:
      let
        base = baseNameOf path;
      in
      !(builtins.elem base [
        "node_modules"
        "dist"
        ".git"
        ".github"
      ]);
  };

  # Refresh whenever package-lock.json changes; see nix/README.md.
  npmDepsHash = "sha256-18ge4+7G9LhOs2kpJ132c2oDDV06ZBTG46GCr8ZRrdY=";

  dontNpmBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/${pname} $out/bin
    cp server.js package.json $out/lib/${pname}/
    cp -r node_modules $out/lib/${pname}/node_modules

    makeWrapper ${nodejs}/bin/node $out/bin/${pname} \
      --add-flags "$out/lib/${pname}/server.js"

    runHook postInstall
  '';

  meta = {
    description = "Audiobookshelf custom metadata provider for lubimyczytac.pl";
    homepage = "https://github.com/lakafior/lubimyczytac-abs";
    license = lib.licenses.mit;
    mainProgram = pname;
    platforms = lib.platforms.linux;
  };
}
