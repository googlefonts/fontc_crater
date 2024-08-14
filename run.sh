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
export FONTC_CRATER_INPUT=$(realpath "gf-repos-2024-08-12.json")

GENERATED_HTML="$FONTC_CRATER_RESULTS/index.html"
FONTC_REPO=https://github.com/googlefonts/fontc.git
FONTC_DIR=./fontc
FONTC_REQUIREMENTS="$FONTC_DIR/resources/scripts/requirements.txt"
# relative to FONTC_DIR
SCRIPT_PATH=fontc_crater/resources/ci.sh


if [ ! -d venv ]; then
  echo "setting up venv"
  python -m venv venv
  if [ $? -ne 0 ]; then
    echo could not setup venv, exiting
    exit 1
  fi
fi

source venv/bin/activate

echo "fetching fontc"
if git clone $FONTC_REPO $FONTC_DIR ; then
    # install requirements:
    echo "installing requirements"
    pip install -r $FONTC_REQUIREMENTS -c constraints.txt

    cd $FONTC_DIR
    # run the actual script that starts CI:
    chmod +x $SCRIPT_PATH
    ( $SCRIPT_PATH )
    cd ..
fi
echo "cleaning up"
rm -rf $FONTC_DIR
deactivate

# move index.html from results/ to repo root
mv $GENERATED_HTML index.html

# todo: commit and push repo
