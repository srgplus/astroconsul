#!/bin/sh
# Xcode Cloud runs this after cloning, before it builds.
#
# The app target copies public/, capacitor.config.json and config.xml as
# resources, and all three are generated rather than tracked, so a fresh
# clone does not build without them. This makes them the way ci.yml and
# testflight.yml do: the web build, then `cap copy` (not `cap sync`, which
# rewrites Package.swift and fails on this renamed project).
#
# Xcode Cloud's image has Homebrew but no Node.

set -eu

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
brew install node@22
export PATH="$(brew --prefix node@22)/bin:$PATH"
node --version

cd "$CI_PRIMARY_REPOSITORY_PATH/frontend"
npm ci
npm run build
npx cap copy ios
