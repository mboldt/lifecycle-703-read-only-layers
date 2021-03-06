#!/bin/bash

set -euo pipefail

thisdir="$(pwd)"
workdir="${thisdir}/work"
lifecycledir="${workdir}/lifecycle"
#lifecyclebranch="703-read-only-layers-perf" # hash directories
lifecyclebranch="703-read-only-layers-watcher" # file system watcher
builderdir="${workdir}/tiny-builder"
appdir="${workdir}/spring-petclinic-rest"
builder_on="ro-layers-tiny-builder"
builder_off="no-ro-layers-tiny-builder"

mkdir -p "${workdir}"
cd "${workdir}"

# Get, test, and build the custom lifeycle
if [ ! -e lifecycle ]; then
    git clone git@github.com:mboldt/lifecycle.git "${lifecycledir}"
fi
cd "${lifecycledir}"
git checkout "${lifecyclebranch}"
git pull
#go test -v builder_internal_test.go builder.go logger.go analyzer.go  cache.go exporter.go save.go utils.go
make clean unit {build,package}-linux-amd64

# Use this lifecycle in a custom builder
if [ ! -e "${builderdir}" ]; then
  git clone git@github.com:paketo-buildpacks/tiny-builder.git "${builderdir}"
fi
cd "${builderdir}"
git pull
cd "${thisdir}/buildertoml"
go run main.go "${lifecycledir}"/out/*.tgz < "${builderdir}/builder.toml" > "${workdir}/builder.toml"
pack builder create "${builder_off}" --config "${workdir}/builder.toml"
# It's annoying to build and manage multiple builder images just to set an env var for lifecycle feature flag.
# TODO Add a flag to pack to set lifecycle environment variables.
docker build --tag "${builder_on}" "${thisdir}/builder"

# Get the app
if [ ! -e "${appdir}" ]; then
  git clone https://github.com/spring-petclinic/spring-petclinic-rest.git "${appdir}"
fi
cd "${appdir}"
git pull

# Build the app with the custom builder
appimg="spring-petclinic-rest"

for i in $(seq 5); do
time pack build "${appimg}" \
     --verbose \
     --path "${appdir}" \
     --trust-builder \
     --builder "${builder_on}"
done

for i in $(seq 5); do
time pack build "$appimg" \
     --verbose \
     --path "$appdir" \
     --trust-builder \
     --builder "${builder_off}"
done
