#!/usr/bin/env bash
set -euo pipefail

WSL_DISTRO=NixOS
REMOTE_DIR=.windows-projects
WSL_BUILD_DIR=.wsl-build
WSL_REMOTE=host
WIN_STASH_REF=refs/wsl-bridge/win
DETACH=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -D|--distro)       WSL_DISTRO=$2;  shift 2 ;;
        -R|--remote-dir)   REMOTE_DIR=$2;  shift 2 ;;
        --wsl-remote)      WSL_REMOTE=$2;  shift 2 ;;
        --detach)          DETACH=true;    shift   ;;
        --force)           FORCE=true;     shift   ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# ── Windows half ──────────────────────────────────────────────────────────────
if [[ "${OSTYPE}" == msys* || "${OSTYPE}" == cygwin* ]]; then
    current_ref() {
        local repo=$1 ref
        ref=$(git -C "$repo" rev-parse --abbrev-ref HEAD)
        [[ "$ref" != HEAD ]] || ref=$(git -C "$repo" rev-parse --short HEAD)
        printf '%s\n' "$ref"
    }

    REPO_DIR=$(git rev-parse --show-toplevel)
    WIN_CLONE="/mnt$(cygpath -u "$REPO_DIR")"
    SCRIPT_WSL="/mnt$(cygpath -u "$0")"

    REF=$(current_ref "$REPO_DIR")
    WIN_HEAD=$(git -C "$REPO_DIR" rev-parse --short HEAD)
    WIN_STASH_HASH=$(git -C "$REPO_DIR" stash create -u "wsl-sync-$REF-$WIN_HEAD")
    [[ -n "$WIN_STASH_HASH" ]] && git -C "$REPO_DIR" update-ref "$WIN_STASH_REF" "$WIN_STASH_HASH"

    OPTS=(-D "$WSL_DISTRO" -R "$REMOTE_DIR" --wsl-remote "$WSL_REMOTE")
    $DETACH && OPTS+=(--detach)
    $FORCE  && OPTS+=(--force)
    OPTS_STR=$(printf '%q ' "${OPTS[@]}")
    exec wsl -d "$WSL_DISTRO" -- bash -lc \
        "_SYNC_WIN_CLONE='$WIN_CLONE' _SYNC_REF='$REF' _SYNC_WIN_HEAD='$WIN_HEAD' _SYNC_WIN_STASH_HASH='$WIN_STASH_HASH' exec bash '$SCRIPT_WSL' $OPTS_STR"
fi

# ── WSL half ──────────────────────────────────────────────────────────────────
exec 3>&1 >&2

WIN_CLONE=${_SYNC_WIN_CLONE:?}
REF=${_SYNC_REF:?}
WIN_HEAD=${_SYNC_WIN_HEAD:?}
WIN_STASH_HASH=${_SYNC_WIN_STASH_HASH:-}

SAFE_REF=$(printf '%s' "$REF" | tr '/' '-')
REPO_NAME=$(basename "$WIN_CLONE")
[[ "$REMOTE_DIR" == /* ]] || REMOTE_DIR="$HOME${REMOTE_DIR:+/$REMOTE_DIR}"
WSL_CLONE="$REMOTE_DIR/$REPO_NAME"

if $DETACH; then
    DEST="$WSL_CLONE/$WSL_BUILD_DIR/$SAFE_REF-$WIN_HEAD"
else
    DEST="$WSL_CLONE"
fi

cleanup() (
    git -C "$WSL_CLONE" update-ref -d "$WIN_STASH_REF" 2>/dev/null || true
    if [[ -n "$WIN_STASH_HASH" ]]; then
        git -C "$WIN_CLONE" update-ref -d "$WIN_STASH_REF" 2>/dev/null || true
    fi
)
trap cleanup EXIT

if [[ -e "$WSL_CLONE" ]]; then
    actual_url=$(git -C "$WSL_CLONE" remote get-url "$WSL_REMOTE" 2>/dev/null || true)
    if [[ -z "$actual_url" ]]; then
        git -C "$WSL_CLONE" remote add "$WSL_REMOTE" "$WIN_CLONE"
    elif [[ "$actual_url" != "$WIN_CLONE" ]]; then
        echo "error: remote '$WSL_REMOTE' in '$WSL_CLONE' points to '$actual_url'; expected '$WIN_CLONE'" >&2
        echo "use --wsl-remote to choose a different remote name" >&2
        exit 1
    fi
else
    git clone --origin "$WSL_REMOTE" --single-branch --branch "$REF" --config core.fileMode=false "$WIN_CLONE" "$WSL_CLONE"
fi
git -C "$WSL_CLONE" fetch "$WSL_REMOTE" "$REF"

if git -C "$WSL_CLONE" show-ref --verify --quiet "refs/remotes/$WSL_REMOTE/$REF"; then
    wsl_ref="$WSL_REMOTE/$REF"
else
    wsl_ref="$REF"
fi

if $DETACH; then
    if [[ ! -e "$DEST/.git" ]]; then
        git -C "$WSL_CLONE" worktree add --detach "$DEST" "$wsl_ref"
    else
        git -C "$DEST" reset --hard -q "$wsl_ref"
        git -C "$DEST" clean -fdq
    fi
else
    actual_branch=$(git -C "$WSL_CLONE" rev-parse --abbrev-ref HEAD)
    if [[ "$actual_branch" != "$REF" ]]; then
        if ! $FORCE; then
            echo "error: WSL clone is on '$actual_branch' but Windows is on '$REF'" >&2
            echo "  checkout '$REF' in WSL first, use --force to discard local state, or use --detach to build in a separate worktree" >&2
            exit 1
        fi
        git -C "$WSL_CLONE" checkout -f -B "$REF" "$wsl_ref"
    elif git -C "$WSL_CLONE" merge-base --is-ancestor HEAD "$wsl_ref"; then
        git -C "$WSL_CLONE" merge --ff-only -q "$wsl_ref"
    else
        if ! $FORCE; then
            echo "error: WSL '$REF' has diverged from Windows; use --force to reset" >&2
            exit 1
        fi
        git -C "$WSL_CLONE" reset --hard -q "$wsl_ref"
    fi
fi

if [[ -n "$WIN_STASH_HASH" ]]; then
    git -C "$WSL_CLONE" fetch "$WIN_CLONE" "$WIN_STASH_REF:$WIN_STASH_REF"
    stash_commit=$(git -C "$WSL_CLONE" rev-parse "$WIN_STASH_REF")
    if ! git -C "$DEST" stash apply --index "$stash_commit"; then
        if ! $DETACH; then
            git -C "$DEST" reset --hard HEAD 2>/dev/null || true
        fi
        echo "error: windows changes could not be applied to '$DEST'" >&2
        exit 1
    fi
fi

printf '%s\n' "$DEST" >&3
