#!/bin/sh
# Installs AltC for this user on macOS or Linux, with a Bun of its own, so
# nothing else is needed: no Node, no npm, no sudo (plan 2026-09-25-install).
#
#   curl -fsSL https://raw.githubusercontent.com/adit-firdaus/altc-public/main/install.sh | sh
#
# Running it again updates AltC, and restarts the server when it runs.
# Everything comes from AltC's public releases on GitHub: altc's bundle, and a
# copy of Bun's own release (scripts/release.ts). Each is checked against its
# sha256 in the release's release.txt before it is used.
#
# Settings, from the environment:
#   ALTC_VERSION=1.2.3       a version to install (default: the latest)
#   ALTC_HOME=~/.altc        where it goes
#   ALTC_NO_MODIFY_PATH=1    leave shell startup files alone
#   ALTC_NO_RESTART=1        leave a running server on the version it runs
#   ALTC_BASE=https://...    another copy of the releases (for testing)
#
# Wrapped in main, so a download cut short runs nothing.

set -eu

main() {
  base=${ALTC_BASE:-https://github.com/adit-firdaus/altc-public/releases}
  base=${base%/}
  # Only a test's own server may be plain http.
  case $base in http://127.0.0.1:* | http://localhost:*) proto='=http,https' ;; *) proto='=https' ;; esac
  root=${ALTC_HOME:-$HOME/.altc}
  case $root in /*) ;; *) fail "ALTC_HOME must be an absolute path, not $root" ;; esac

  if [ -t 1 ]; then bold=$(printf '\033[1m'); dim=$(printf '\033[2m'); red=$(printf '\033[31m'); plain=$(printf '\033[0m'); else bold='' dim='' red='' plain=''; fi

  need uname
  need tar
  need mkdir
  if command -v curl >/dev/null 2>&1; then fetcher=curl; elif command -v wget >/dev/null 2>&1; then fetcher=wget; else fail 'curl or wget is needed to download AltC'; fi

  platform
  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t altc)
  trap 'rm -rf "$tmp"' EXIT INT TERM

  # The latest release says which version it is; GitHub sends latest/download/ to it.
  if [ -n "${ALTC_VERSION:-}" ]; then
    version=$(printf '%s' "$ALTC_VERSION" | tr -d ' \r\n')
    case $version in '' | */* | .*) fail "No such altc version: $version" ;; esac
    release=$(fetch "$base/download/v$version/release.txt" "There is no altc $version at $base")
  else
    release=$(fetch "$base/latest/download/release.txt" "No answer from $base")
    version=$(field version "$release")
    case $version in '' | */* | .*) fail "The latest release at $base names no version" ;; esac
  fi
  bun_version=$(field bun "$release")
  bun=$(install_bun)
  install_altc
  write_shim
  old=$(cat "$root/current" 2>/dev/null || true)
  if [ -n "$old" ] && [ "$old" != "$version" ]; then printf '%s\n' "$old" >"$root/previous"; fi
  printf '%s\n' "$version" >"$root/current.tmp" && mv -f "$root/current.tmp" "$root/current"
  prune
  on_path
  after
}

say() { printf '%s\n' "$*" >&2; }
fail() {
  printf '%saltc install:%s %s\n' "${red:-}" "${plain:-}" "$*" >&2
  exit 1
}
need() { command -v "$1" >/dev/null 2>&1 || fail "$1 is needed to install AltC"; }

download() {
  if [ "$fetcher" = curl ]; then curl -fsSL --retry 3 --proto "$proto" -o "$2" "$1"; else wget -q -O "$2" "$1"; fi || fail "Couldn't download $1"
}
# A URL's text; $2 says what went wrong when there is none.
fetch() {
  if [ "$fetcher" = curl ]; then curl -fsL --retry 3 --proto "$proto" "$1"; else wget -q -O - "$1"; fi || fail "${2:-No answer from $1}"
}

# A value from release.txt's `name value` lines.
field() { printf '%s\n' "$2" | sed -n "s/^$1 //p" | tr -d '\r' | head -n 1; }

# The sha256 of a file, in hex.
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 -r "$1" | cut -d' ' -f1
  else fail 'sha256sum, shasum or openssl is needed to check the download'
  fi
}

check() {
  [ -n "$2" ] || fail "The release gave no checksum for $3"
  [ "$(sha256 "$1")" = "$2" ] || fail "$3 doesn't match its checksum; nothing was changed"
}

platform() {
  os=$(uname -s)
  arch=$(uname -m)
  case $os in
    Darwin) os=darwin ;;
    Linux) os=linux ;;
    MINGW* | MSYS* | CYGWIN*) fail "On Windows, run this in PowerShell instead: irm https://raw.githubusercontent.com/adit-firdaus/altc-public/main/install.ps1 | iex" ;;
    *) fail "AltC runs on macOS, Linux and Windows, not $os" ;;
  esac
  case $arch in
    x86_64 | amd64) arch=x64 ;;
    arm64 | aarch64) arch=aarch64 ;;
    *) fail "AltC runs on x64 and arm64, not $arch" ;;
  esac
  # A shell under Rosetta says x64 on an Apple silicon Mac; its own Bun is faster.
  if [ "$os" = darwin ] && [ "$arch" = x64 ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" = 1 ]; then arch=aarch64; fi
  suffix=''
  if [ "$os" = linux ] && { [ -f /etc/alpine-release ] || ldd --version 2>&1 | grep -qi musl; }; then suffix=-musl; fi
  baseline=''
  if [ "$arch" = x64 ]; then
    if [ "$os" = linux ] && ! grep -qi avx2 /proc/cpuinfo 2>/dev/null; then baseline=-baseline; fi
    if [ "$os" = darwin ] && ! sysctl -a 2>/dev/null | grep -q 'machdep.cpu.*AVX2'; then baseline=-baseline; fi
  fi
  target=$os-$arch$suffix$baseline
}

install_bun() {
  dir=$root/bun/$bun_version
  if [ -x "$dir/bun" ] && [ "$("$dir/bun" --version 2>/dev/null)" = "$bun_version" ]; then
    printf '%s' "$dir/bun"
    return
  fi
  say "${dim}Bun $bun_version for $target${plain}"
  want=$(field "bun-$target" "$release")
  [ -n "$want" ] || fail "altc $version has no Bun for $target"
  download "$base/download/bun-v$bun_version/bun-$target.tgz" "$tmp/bun.tgz"
  check "$tmp/bun.tgz" "$want" "Bun $bun_version"
  mkdir -p "$tmp/bun"
  tar -xzf "$tmp/bun.tgz" -C "$tmp/bun"
  chmod 755 "$tmp/bun/bun"
  if ! "$tmp/bun/bun" --version >/dev/null 2>&1; then
    if [ -n "$suffix" ]; then fail 'Bun would not start. On Alpine it needs: apk add libstdc++ libgcc'; fi
    fail 'Bun would not start on this machine'
  fi
  mkdir -p "$dir"
  mv -f "$tmp/bun/bun" "$dir/bun"
  printf '%s' "$dir/bun"
}

install_altc() {
  dest=$root/versions/$version
  if [ -f "$dest/.installed" ]; then
    say "${dim}altc $version is installed already${plain}"
    return
  fi
  say "${dim}altc $version${plain}"
  download "$base/download/v$version/altc-$version.tgz" "$tmp/altc.tgz"
  check "$tmp/altc.tgz" "$(field sha256 "$release")" "altc $version"
  stage=$root/versions/.$version.$$
  rm -rf "$stage"
  mkdir -p "$stage"
  tar -xzf "$tmp/altc.tgz" -C "$stage" --strip-components 1 || { rm -rf "$stage"; fail "Couldn't unpack altc $version"; }
  : >"$stage/.installed"
  rm -rf "$dest"
  mv "$stage" "$dest"
}

# Single quotes around a path, for a shell script.
quoted() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

write_shim() {
  mkdir -p "$root/bin"
  {
    printf '#!/bin/sh\n# Written by the AltC installer: altc %s on its own Bun. Run the installer again to update.\n' "$version"
    printf 'exec %s %s "$@"\n' "$(quoted "$bun")" "$(quoted "$root/versions/$version/dist/cli.js")"
  } >"$root/bin/altc.tmp"
  chmod 755 "$root/bin/altc.tmp"
  mv -f "$root/bin/altc.tmp" "$root/bin/altc"
}

# Keeps this version and the one before it, to go back to. A terminal host
# from before an update runs on from what it loaded, even once its files go.
prune() {
  keep=$(cat "$root/previous" 2>/dev/null || true)
  for d in "$root"/versions/* "$root"/versions/.*.*; do
    [ -d "$d" ] || continue
    v=$(basename "$d")
    case $v in . | ..) continue ;; esac
    [ "$v" = "$version" ] || [ "$v" = "$keep" ] || rm -rf "${root:?}/versions/$v"
  done
  for d in "$root"/bun/*; do
    [ -d "$d" ] && [ "$(basename "$d")" != "$bun_version" ] && rm -rf "$d"
  done
  return 0
}

on_path() {
  bin=$root/bin
  case ":$PATH:" in *":$bin:"*) return ;; esac
  path_note="${bold}export PATH=\"$bin:\$PATH\"${plain}"
  [ -z "${ALTC_NO_MODIFY_PATH:-}" ] || return 0
  shell=$(basename "${SHELL:-sh}")
  case $shell in
    zsh) rc=${ZDOTDIR:-$HOME}/.zshrc line="export PATH=\"$bin:\$PATH\"" ;;
    bash) if [ "$os" = darwin ]; then rc=$HOME/.bash_profile; else rc=$HOME/.bashrc; fi; line="export PATH=\"$bin:\$PATH\"" ;;
    fish) rc=${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/altc.fish line="fish_add_path -g \"$bin\"" ;;
    *) rc=$HOME/.profile line="export PATH=\"$bin:\$PATH\"" ;;
  esac
  if [ -f "$rc" ] && grep -qF "$bin" "$rc"; then
    added_to=$rc
    return
  fi
  mkdir -p "$(dirname "$rc")"
  printf '\n# altc\n%s\n' "$line" >>"$rc"
  added_to=$rc
}

after() {
  altc=$root/bin/altc
  say ""
  say "${bold}altc $version is installed${plain} ${dim}in $root${plain}"
  other=$(command -v altc 2>/dev/null || true)
  if [ -n "$other" ] && [ "$other" != "$altc" ]; then say "${dim}Another altc comes first on your PATH ($other). Remove it to use this one.${plain}"; fi
  if [ -n "${added_to:-}" ]; then say "$root/bin is on your PATH from $added_to. Open a new terminal, or run: $path_note"
  elif [ -n "${path_note:-}" ]; then say "Add it to your PATH: $path_note"
  fi
  # A server running already: move it onto this version.
  if [ -z "${ALTC_NO_RESTART:-}" ] && "$altc" status </dev/null >/dev/null 2>&1; then
    say "${dim}Restarting the server on the new version…${plain}"
    "$altc" restart </dev/null || say "The restart didn't finish. Run: altc restart"
  else
    say "Then start it: ${bold}altc start${plain}"
  fi
}

main "$@"
