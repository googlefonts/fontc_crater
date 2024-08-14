# `fontc_crater` CI

This repository contains a script for running `fontc_crater` (a tool for running
the [`fontc`] font compiler against a large number of inputs) in a CI
environment.

The actual `fontc_crater` binary lives in the [`fontc`] repo; this repo contains
a barebones script for checking out and running the latest version of
`fontc_crater`, as well as collecting the results.

[`fontc`]: https://github.com/googlefonts/fontc
