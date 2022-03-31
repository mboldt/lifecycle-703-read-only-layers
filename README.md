# Read-only Layers Performance Test

This repository captures the experiments for buildpacks/lifecycle#703, to test the performance impact of ensuring buildpacks respect read-only layers.

The accompanying modified lifecycle code lives at https://github.com/mboldt/lifecycle/tree/703-read-only-layers-perf.

## Hashing Layers

I initially intended to use the [dirhash](https://pkg.go.dev/golang.org/x/mod/sumdb/dirhash) package from `go mod`, but it choked on a layer that contained a symbolic link to a directory.
So, I implemented a directory hashing function in https://github.com/mboldt/lifecycle/blob/703-read-only-layers-perf/hasher.go.
To get the hash of a layer directory, it basically creates a [Merkle tree](https://en.wikipedia.org/wiki/Merkle_tree).
To hash a directory, it takes the sha256 hash of the concatenation of the hash and path of each of its children:

```
<hash> <path>
```

Where `<path>` is the name of the child, and `<hash>` depends on the type of the child:

- For a file, `<hash>` is the sha256 hash of the file contents.
- For a link, `<hash>` is the sha256 hash of the target of the link.
- For a directory, `<hash>` is the directory hash of the child directory.

It also checks for modifications of the `<layer>.toml` files, with a simple sha256 hash.

## Experiment

The [main.sh](main.sh) script builds the modified lifecycle.
The lifecycle code uses an environment variable `CNB_LIFECYCLE_RO_LAYERS` as a feature flag to enable the read-only layers detection.
It also measures and prints the duration of these checks to see how long they take.

For a builder, it uses [paketo-buildpacks/tiny-builder](https://github.com/paketo-buildpacks/tiny-builder) as a base, and injects the modified lifecycle.
It creates two versions of the builder: one with the feature flag set, and one without it.
If we want to run end-to-end comparisons, they are both available.

It uses [spring-petclinic/spring-petclinic-rest](https://github.com/spring-petclinic/spring-petclinic-rest) as the target application.

## Results

Running this experiment, the read-only layers check takes about 14s total time (1.7--1.9 seconds after each of 8 buildpacks), of a total build time of 27 seconds.
This nearly doubles the build time.

Perhaps there is a more efficient change detection mechanism, like a filesystem watcher.

It did emit warnings about some of the buildpacks modifying layers which they did not create:

```
Warning: buildpack paketo-buildpacks/bellsoft-liberica changed layer paketo-buildpacks_bellsoft-liberica, which it did not create
Warning: buildpack paketo-buildpacks/syft changed layer paketo-buildpacks_syft, which it did not create
Warning: buildpack paketo-buildpacks/maven changed layer paketo-buildpacks_maven, which it did not create
Warning: buildpack paketo-buildpacks/spring-boot changed layer paketo-buildpacks_spring-boot, which it did not create
```

These look like they might be false-positives, i.e., the restorer recovered these layers, and the modifying buildpacks actually do "own" them.
This may be a major complication in detecting and enforcing read-only layers.
