#!/usr/bin/env bash
set -euo pipefail

FLAKE_DIR=
REMOTE_DIR=.windows-projects
OUTPUT_DIR=
WSL_DISTRO=NixOS
WSL_REMOTE=
TARGETS=()
WIN_ONLY=false
DETACH=true

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--flake-dir)    FLAKE_DIR=$2;                         shift 2 ;;
        -R|--remote-dir)   REMOTE_DIR=$2; WIN_ONLY=true;         shift 2 ;;
        -o|--output-dir)   OUTPUT_DIR=$2;                        shift 2 ;;
        -D|--distro)       WSL_DISTRO=$2; WIN_ONLY=true;         shift 2 ;;
        --wsl-remote)      WSL_REMOTE=$2; WIN_ONLY=true;         shift 2 ;;
        --no-detach)       DETACH=false;                         shift   ;;
        -*) echo "Unknown argument: $1" >&2; exit 1 ;;
        *) TARGETS+=("$1"); shift ;;
    esac
done

REPO_DIR=$(git rev-parse --show-toplevel)
[[ ${#TARGETS[@]} -gt 0 ]] || TARGETS=(default)

if [[ "${OSTYPE}" == msys* || "${OSTYPE}" == cygwin* ]]; then
    SCRIPT_MSYS=$(cygpath -ua "$0")
    SYNC_SCRIPT="$(dirname "$SCRIPT_MSYS")/sync-wsl-remote.sh"
    TMP_SCRIPT="/tmp/wsl-build-$$.sh"
    wsl -d "$WSL_DISTRO" -- bash -c "cp '/mnt${SCRIPT_MSYS}' '$TMP_SCRIPT'"
    WIN_CLONE="/mnt$(cygpath -u "$REPO_DIR")"
    WIN_OUTPUT="$WIN_CLONE/${OUTPUT_DIR:-output}"
    SYNC_OPTS=(-D "$WSL_DISTRO")
    $DETACH && SYNC_OPTS+=(--detach)
    [[ -n "$REMOTE_DIR" ]] && SYNC_OPTS+=(--remote-dir "$REMOTE_DIR")
    [[ -n "$WSL_REMOTE" ]] && SYNC_OPTS+=(--wsl-remote "$WSL_REMOTE")
    WORKTREE=$("$SYNC_SCRIPT" "${SYNC_OPTS[@]}")
    exec wsl -d "$WSL_DISTRO" -- bash -lc "cd '$WORKTREE' && exec bash '$TMP_SCRIPT' --output-dir '$WIN_OUTPUT' ${TARGETS[*]}"
fi

$WIN_ONLY && echo "warning: --distro, --remote-dir, --wsl-remote have no effect on Linux" >&2

FLAKE_DIR=${FLAKE_DIR:-$REPO_DIR}
OUTPUT_DIR=${OUTPUT_DIR:-$FLAKE_DIR/output}

cd "$FLAKE_DIR"
echo "Building flake outputs: ${TARGETS[*]}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

for t in "${TARGETS[@]}"; do
    nix build "path:$(pwd)#$t" --out-link "$tmp/result-$t"
done

mkdir -p "$OUTPUT_DIR"
for link in "$tmp/result-"*; do
    rm -rf "${OUTPUT_DIR:?}/$(basename "$link")"
    cp -rL "$link" "$OUTPUT_DIR/"
done
