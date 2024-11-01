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

**python dependencies**: the set of python dependencies that are run in CI is
controlled by a `constraints.txt` file in the `fontc` repo. See the
[`fontc_crater README`][crater-readme] in that repository for information on
updating that file.

[`fontc`]: https://github.com/googlefonts/fontc
[crater-readme]: https://github.com/googlefonts/fontc/blob/main/fontc_crater/README.md
