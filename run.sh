#!/usr/bin/env bash

# this script is intended to be the entry point for running fontc_crater
# in a CI environment.
#
# This script should be copied into a new directory, and a a work scheduler
# (such as cron) should be setup to run it regularly (for instance, each night)
#
# this script is intentionally minimal and not intended to change much; all it
# should do is clone the fontc repo, and then call another script in that repo
# which will handle actually starting crater.

# the script we call in the fontc repo will use these variables to set
# arguments on fontc_crater
export FONTC_CRATER_RESULTS=$(realpath  ./results)
export FONTC_CRATER_INPUT=$(realpath "gf-repos-2024-09-23.json")

GENERATED_HTML="$FONTC_CRATER_RESULTS/index.html"
LOCKFILE="$FONTC_CRATER_RESULTS/CRATER.lock"
FONTC_REPO=https://github.com/googlefonts/fontc.git
FONTC_DIR=./fontc
FONTC_REQUIREMENTS="$FONTC_DIR/resources/scripts/requirements.txt"
# relative to FONTC_DIR
SCRIPT_PATH=fontc_crater/resources/ci.sh
GITHUB_TOKEN=$(<"GITHUB_TOKEN")

cleanup() {
    echo "cleaning up"
    rm -rf $FONTC_DIR
    rm $LOCKFILE
    deactivate
    # if we crashed after writing some files, stash them
    git add .
    git stash save "changes found at cleanup $(date '+%a %h %d %Y %H:%M')"
}

# acquire lock, or bail:
if [ -f $LOCKFILE ]; then
    echo "$LOCKFILE exists (CI is already running, or failed and requires manual cleanup)"
    exit 1
else
    touch $LOCKFILE
fi

# make sure that the upstream repo is configured to authenticate with our token:
git remote set-url origin "https://$GITHUB_TOKEN:x-oauth-basic@github.com/googlefonts/fontc_crater.git"

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

if [ -d venv ]; then
    rm -rf venv
fi

echo "setting up venv"
python -m venv venv
if [ $? -ne 0 ]; then
    echo could not setup venv, exiting
    cleanup
    exit 1
fi

source venv/bin/activate

echo "fetching fontc"
if git clone $FONTC_REPO $FONTC_DIR ; then
    # install requirements:
    echo "installing requirements"
    pip install -r $FONTC_REQUIREMENTS

    cd $FONTC_DIR
    # run the actual script that starts CI:
    chmod +x $SCRIPT_PATH
    ( $SCRIPT_PATH )
    if [ $? -ne 0 ]; then
        echo script did not finish successfully, exiting
        cleanup
        exit 1
    fi

    cd ..
fi

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
fi

# finally, cleanup if we got this far
cleanup
