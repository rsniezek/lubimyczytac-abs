# Nix packaging

The repository is a flake: `flake.nix` at the root exposes the package and a
NixOS module, `nix/package.nix` is the derivation and `nix/module.nix` the
module. `flake.lock` is committed and pins `nixpkgs`, so builds are repeatable
without a `flake.nix` edit.

| Output | What it is |
| --- | --- |
| `packages.<system>.default`, `packages.<system>.lubimyczytac-abs` | the provider (`bin/lubimyczytac-abs`) |
| `nixosModules.default`, `nixosModules.lubimyczytac-abs` | `services.lubimyczytac-abs` |
| `checks.<system>.default` | the package itself, so `nix flake check` builds it |
| `formatter.<system>` | `nixfmt-tree`, so `nix fmt` formats every Nix file in the tree |

Supported systems are `x86_64-linux` and `aarch64-linux`.

## Everyday commands

```console
$ nix build .#default      # build the package into ./result
$ nix run .#default        # run it without Docker; HOST/PORT select the address
$ nix flake check          # evaluate the flake and build the checks
$ nix fmt                  # format every Nix file in the tree (nixfmt, RFC 166 style)
$ nix flake update         # bump flake.lock to the latest nixpkgs
```

Run `nix fmt` and `nix flake check` before pushing a change that touches
anything under `nix/` or `flake.nix`. `nix flake check` is the closest thing to
CI here: it builds `packages.default` through `checks.default`, so a broken
derivation (most often a stale `npmDepsHash`, see below) fails locally instead
of in someone's rebuild.

## How the package is built

`buildNpmPackage` installs the dependency tree from `package-lock.json` and the
install phase copies `server.js` plus `node_modules` into `$out/lib` and wraps it
in a `bin/lubimyczytac-abs` launcher.

The Dockerfile runs `esbuild` to produce a single bundled file. That step only
exists to keep the image small; running `server.js` with the dependency tree does
the same work, so the derivation sets `dontNpmBuild = true` and skips it. This
also means `server.js` must stay runnable directly (no build-time codegen). If
that ever changes, drop `dontNpmBuild` and add the needed build hook.

Dev dependencies are fetched as part of the tree because `npm ci` installs them;
they are simply never executed.

## When `package-lock.json` changes: `npmDepsHash`

`npmDepsHash` is a fixed-output hash of the dependency tree that
`buildNpmPackage` prefetches. It is derived from `package.json` and
`package-lock.json`, so **any** dependency change — an upstream bump, a new
dependency, a regenerated lockfile — invalidates it. The build fails loudly
rather than silently using a different tree:

```text
error: hash mismatch in fixed-output derivation '/nix/store/…-lubimyczytac-abs-1.1.0-npm-deps.drv':
         specified: sha256-18ge4+7G9LhOs2kpJ132c2oDDV06ZBTG46GCr8ZRrdY=
            got:    sha256-…
```

Two ways to get the new value:

1. Ask the prefetcher (fast, no failed build):

   ```console
   $ nix run nixpkgs#prefetch-npm-deps -- package-lock.json
   sha256-…
   ```

   Paste the printed hash into `npmDepsHash` in `nix/package.nix`.

2. Let the build tell you: set `npmDepsHash = lib.fakeHash;`, run
   `nix build .#default`, and copy the `got:` value out of the error. Remember
   to replace `lib.fakeHash` afterwards — the flake will never build with it.

Then confirm with `nix build .#default` (or `nix flake check`, which builds the
same derivation).

A one-line change to `nix/package.nix` that only updates `npmDepsHash` is
expected whenever the lockfile moves; it is not a code change and does not need
to be split into its own commit if the lockfile change is in the same PR.

## Version

`package.json` is the single source of truth: `nix/package.nix` reads it with
`lib.importJSON ../package.json`. Bump `version` there only — do not duplicate
it in the derivation. The version ends up in the store path
(`lubimyczytac-abs-1.1.0`), so it also makes rebuilds obvious.

## Node.js version

The derivation uses nixpkgs' default `nodejs`. The Docker image pins Node 20. If
upstream starts using a language or runtime feature newer than nixpkgs' default,
pin `nodejs` in `nix/package.nix` (`nodejs_22`, …) instead of changing the
default globally.

## NixOS module

```nix
services.lubimyczytac-abs = {
  enable = true;
  # host = "127.0.0.1"; # default; set another address only if ABS runs elsewhere
  # port = 3011;        # default 3000
  # openFirewall = true; # only useful when host is not loopback
};
```

The service reads `HOST` and `PORT`, runs as a `DynamicUser`, keeps the
filesystem read-only (`ProtectSystem = "strict"`, `ProtectHome`, `PrivateTmp`)
and is stateless — the provider's cache is in memory.

**Prerequisite:** `HOST` support in `server.js` (it previously bound every
interface from `PORT` alone). A checkout that predates it ignores the module's
`HOST=127.0.0.1` and listens on all interfaces, so make sure the `HOST` change
is in before enabling the module on an untrusted network.

Adding the provider in Audiobookshelf ("Custom Metadata Providers") is unchanged:
URL `http://127.0.0.1:<port>`, any non-empty authorization header value.

`nix flake check` does not evaluate the module, so test a module change by
rebuilding a host that imports it (or by evaluating a throwaway system, see
"Smoke test"). The option surface is small; a typo in `nix/module.nix` will
otherwise only show up at deploy time.

## Smoke test

There is no test suite; the flake checks cover evaluation and build. To sanity
check a running instance, start it in one shell:

```console
$ nix run .#default                         # or HOST/PORT as needed
```

and probe it from another:

```console
$ curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/search
401
$ curl -s -H 'Authorization: x' 'http://127.0.0.1:3000/search'
{"error":"Query parameter is required"}
$ curl -s -H 'Authorization: x' 'http://127.0.0.1:3000/search?query=Kinslayer' | head -c 300
```

A `401` without the header and a `400` with it mean the server is up. The last
request needs network access to lubimyczytac.pl.

To evaluate the module without building a host:

```console
$ nix eval --impure --raw --expr '
  let f = builtins.getFlake (toString ./.);
  in (f.inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ f.nixosModules.default { services.lubimyczytac-abs.enable = true; } ];
  }).config.systemd.services.lubimyczytac-abs.serviceConfig.ExecStart'
```

## Submitting to nixpkgs

If this flake is not accepted upstream, the same derivation can live in nixpkgs:
`pkgs/by-name/lu/lubimyczytac-abs/package.nix` (with `npmDepsHash`, `meta.license`
and a `maintainers` entry), plus `nixos/modules/services/misc/lubimyczytac-abs.nix`
and a `nixos/tests/lubimyczytac-abs.nix` that starts the service and curls
`/search`. The version must be a literal there (nixpkgs packages are not
self-referencing flakes), and the hash workflow above applies unchanged.
