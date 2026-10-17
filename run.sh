#!/usr/bin/env bash

# this script is intended to be the entry point for running fontc_crater
# in a CI environment.
#
# This script should be copied into a new directory, and a a work scheduler
# (such as cron) should be setup to run it regularly (for instance, each night)
#
# this script is intentionally minimal and not intended to change much; all it
# should do is update its fontc checkout, and then call another script in that
# repo which will handle actually starting crater.

# the github repo this instance pushes its results and status to
CRATER_REPO=googlefonts/fontc_crater
# status.json is the only file on this branch of CRATER_REPO
STATUS_BRANCH=status
# where we write status.json before publishing it
STATUS_DIR="$PWD/status"

# the script we call in the fontc repo will use these variables to set
# arguments on fontc_crater
export FONTC_CRATER_RESULTS=$(realpath  ./results)
export FONTC_CRATER_INPUT=$(realpath "targets.json")
# crater writes its progress here; we publish it along with our own status
export FONTC_CRATER_PROGRESS_FILE="$STATUS_DIR/progress.json"
# and the report reads what we publish from here
export FONTC_CRATER_STATUS_URL="https://raw.githubusercontent.com/$CRATER_REPO/refs/heads/$STATUS_BRANCH/status.json"

GENERATED_HTML="$FONTC_CRATER_RESULTS/index.html"
LOCKFILE="$FONTC_CRATER_RESULTS/CRATER.lock"
FONTC_REPO=https://github.com/googlefonts/fontc.git
# FONTC_DIR (including its target dir) and the venv are kept between runs
FONTC_DIR=./fontc
# relative to FONTC_DIR
FONTC_REQUIREMENTS="resources/scripts/requirements.txt"
SCRIPT_PATH=fontc_crater/resources/ci.sh
GITHUB_TOKEN=$(<"GITHUB_TOKEN")
PYTHON_EXEC=python3.13
# what the venv was built from; it is rebuilt when this changes
VENV_STAMP=venv/crater-stamp
CRATER_ROOT=$(pwd)

# crater builds fontc with these set; match them in crater's own build, so the
# two builds don't keep invalidating each other
export VERGEN_GIT_DESCRIBE=VERGEN_IDEMPOTENT_OUTPUT
export VERGEN_GIT_SHA=VERGEN_IDEMPOTENT_OUTPUT

cleanup() {
    echo "cleaning up"
    # we may have failed while inside FONTC_DIR
    cd "$CRATER_ROOT"
    rm $LOCKFILE
    deactivate
    # if we crashed after writing some files, stash them
    git add .
    git stash save "changes found at cleanup $(date '+%a %h %d %Y %H:%M')"
}

# usage: write_status running | write_status finished EXIT_CODE
write_status() {
    local now finished=null exit_code=null progress=null
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if [ "$1" = finished ]; then
        finished="\"$now\""
        exit_code=$2
    fi
    if [ -f "$FONTC_CRATER_PROGRESS_FILE" ]; then
        progress=$(<"$FONTC_CRATER_PROGRESS_FILE")
    fi
    printf '{"state": "%s", "started": "%s", "updated": "%s", "finished": %s, "exit_code": %s, "progress": %s}\n' \
        "$1" "$STARTED" "$now" "$finished" "$exit_code" "$progress" > "$STATUS_DIR/status.tmp"
    mv "$STATUS_DIR/status.tmp" "$STATUS_DIR/status.json"
}

# force-push status.json as the only commit on STATUS_BRANCH. this only uses
# plumbing, so it never touches the index or the working tree.
publish_status() {
    local blob tree commit
    blob=$(git -C "$CRATER_ROOT" hash-object -w "$STATUS_DIR/status.json") || return
    tree=$(printf '100644 blob %s\tstatus.json\n' "$blob" | git -C "$CRATER_ROOT" mktree) || return
    commit=$(git -C "$CRATER_ROOT" commit-tree "$tree" -m "crater status") || return
    git -C "$CRATER_ROOT" push --quiet --force origin "$commit:refs/heads/$STATUS_BRANCH"
}

# republish every minute, so progress shows up and a stuck run can be told
# apart from a slow one
heartbeat() {
    # if we're stopped mid-push, finish the push first
    trap 'exit 0' TERM
    while true; do
        write_status running
        publish_status
        sleep 60 &
        wait $!
    done
}

stop_heartbeat() {
    if [ -n "$HEARTBEAT_PID" ]; then
        kill "$HEARTBEAT_PID" 2>/dev/null
        wait "$HEARTBEAT_PID" 2>/dev/null
        HEARTBEAT_PID=
    fi
}

on_exit() {
    stop_heartbeat
    write_status finished "$1"
    publish_status
}

# true if FONTC_DIR is the top of a clone of FONTC_REPO. if FONTC_DIR is a
# broken repo, git looks upward and finds ours, which we must not touch.
fontc_is_clone() {
    local toplevel
    toplevel=$(git -C "$FONTC_DIR" rev-parse --show-toplevel 2>/dev/null) &&
        [ "$toplevel" = "$(cd "$FONTC_DIR" && pwd -P)" ] &&
        [ "$(git -C "$FONTC_DIR" remote get-url origin)" = "$FONTC_REPO" ]
}

# check out origin/main, discarding everything except cargo's target dir
sync_fontc() {
    git -C "$FONTC_DIR" fetch --quiet --prune origin &&
        git -C "$FONTC_DIR" checkout --quiet --force --detach origin/main &&
        git -C "$FONTC_DIR" clean -ffdxq -e /target/
}

update_fontc() {
    if fontc_is_clone && sync_fontc; then
        return
    fi
    echo "recloning fontc"
    rm -rf "$FONTC_DIR"
    git clone $FONTC_REPO $FONTC_DIR && sync_fontc
}

venv_stamp() {
    $PYTHON_EXEC -c 'import sys; print(sys.version)'
    (cd $FONTC_DIR && shasum -a 256 $FONTC_REQUIREMENTS ttx_diff/pyproject.toml)
}

# acquire lock, or bail:
if [ -f $LOCKFILE ]; then
    echo "$LOCKFILE exists (CI is already running, or failed and requires manual cleanup)"
    exit 1
else
    touch $LOCKFILE
fi

# only after taking the lock, so a run that bails above doesn't clobber the
# status of the one that's actually running
mkdir -p "$STATUS_DIR"
rm -f "$FONTC_CRATER_PROGRESS_FILE"
STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
write_status running
trap 'on_exit $?' EXIT
# otherwise the EXIT trap sees the status of whatever ran last
trap 'exit 130' INT
trap 'exit 143' TERM

# make sure that the upstream repo is configured to authenticate with our token:
git remote set-url origin "https://$GITHUB_TOKEN:x-oauth-basic@github.com/$CRATER_REPO.git"

if [ $? -ne 0 ]; then
    echo "failed to set upstream"
    cleanup
    exit 1
fi

# first make sure this repo is up to date, in case some config changes were pushed
git pull
if [ $? -ne 0 ]; then
    echo "git pull failed, exiting"
    cleanup
    exit 1
fi

heartbeat &
HEARTBEAT_PID=$!

# before the venv, which is installed from (and stamped with) files in fontc
echo "updating fontc"
if ! update_fontc; then
    echo "failed to update fontc, exiting"
    cleanup
    exit 1
fi

stamp=$(venv_stamp)
if [ "$stamp" = "$(cat $VENV_STAMP 2>/dev/null)" ] &&
    venv/bin/python -c 'import ttx_diff' 2>/dev/null; then
    echo "reusing venv"
    source venv/bin/activate
else
    rm -rf venv
    echo "setting up venv for $( $PYTHON_EXEC --version)"
    $PYTHON_EXEC -m venv venv
    if [ $? -ne 0 ]; then
        echo could not setup venv, exiting
        cleanup
        exit 1
    fi

    source venv/bin/activate

    echo "installing requirements"
    (cd $FONTC_DIR && pip install -r $FONTC_REQUIREMENTS) &&
        echo "$stamp" > $VENV_STAMP
fi

cd $FONTC_DIR
# run the actual script that starts CI:
chmod +x $SCRIPT_PATH
# pass our token through to the crater executable, it will use it to
# authenticate to private repos
( export GITHUB_TOKEN=$GITHUB_TOKEN; $SCRIPT_PATH )
if [ $? -ne 0 ]; then
    echo script did not finish successfully, exiting
    cleanup
    exit 1
fi

cd ..

# so it doesn't race the git commands below
stop_heartbeat

# move index.html from results/ to repo root
mv $GENERATED_HTML index.html

## commit and push repo

# before we commit let's stash changes and pull
# in case there's been some maintanance change made upstream
# while we were running:

git add .
git stash save
git pull
git stash pop

git add .
git commit -m 'Automated commit'
if [ $? -eq 0 ]; then
    git push
    if [ $? -ne 0 ]; then
        echo "git push failed, exiting"
        cleanup
        exit 1
    fi
fi

# finally, cleanup if we got this far
cleanup
