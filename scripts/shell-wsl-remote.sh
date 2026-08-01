#!/usr/bin/env bash
set -euo pipefail

WSL_DISTRO=NixOS
REMOTE_DIR=.windows-projects
WSL_REMOTE=
NIX_DEVELOP=false
DETACH=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -D|--distro)     WSL_DISTRO=$2;    shift 2 ;;
        -R|--remote-dir) REMOTE_DIR=$2;    shift 2 ;;
        --wsl-remote)    WSL_REMOTE=$2;    shift 2 ;;
        --nix-develop)   NIX_DEVELOP=true; shift   ;;
        --detach)        DETACH=true;      shift   ;;
        --force)         FORCE=true;       shift   ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

SYNC_OPTS=(-D "$WSL_DISTRO")
[[ -n "$REMOTE_DIR" ]] && SYNC_OPTS+=(--remote-dir "$REMOTE_DIR")
[[ -n "$WSL_REMOTE" ]] && SYNC_OPTS+=(--wsl-remote "$WSL_REMOTE")
$DETACH && SYNC_OPTS+=(--detach)
$FORCE  && SYNC_OPTS+=(--force)
WORKTREE=$("$(dirname "$(cygpath -ua "$0")")/sync-wsl-remote.sh" "${SYNC_OPTS[@]}")

CMD=$([[ "$NIX_DEVELOP" == true ]] && echo "nix develop" || echo "bash")
exec wsl -d "$WSL_DISTRO" -- bash -lc "cd '$WORKTREE' && exec $CMD"
