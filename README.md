# `fontc_crater` CI

This repository contains a script for running `fontc_crater` (a tool for running
the [`fontc`] font compiler against a large number of inputs) in a CI
environment, and the output of those CI runs.

The actual `fontc_crater` binary lives in the [`fontc`] repo; this repo contains
a barebones script for checking out and running the latest version of
`fontc_crater`, as well as collecting the results.

## setup

This is not a general purpose tool. It is expected to be running on at most one
machine at a time.

To get running:

- clone this repository to the running machine
- on github, generate a personal access token that has write access to
  googlefonts/fontc_crater.
- save this token to a file named GITHUB_TOKEN at the directory root.
- use a scheduler like cron or launchd to execute `run.sh` nightly

## updating inputs or fontmake dependencies

**inputs**: The set of inputs that are run are stored in this repo, and specified in
`run.sh`. To change the inputs, add a new inputs file and then modify the
`FONTC_CRATER_INPUT` var in that script.

**fontmake dependencies**: We use `constraints.txt` to ensure that fontmake is
using a consistent set of dependencies between runs. To update these
dependencies, install the desired version of fontmake into a new `venv` and run
`pip freeze` to generate a new constraints list.

[`fontc`]: https://github.com/googlefonts/fontc
