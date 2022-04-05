# Read-only Layers Performance Test

This repository captures the experiments for buildpacks/lifecycle#703, to test the performance impact of ensuring buildpacks respect read-only layers.

## Approach 1: Hashing Layers

We initially intended to use the [dirhash](https://pkg.go.dev/golang.org/x/mod/sumdb/dirhash) package from `go mod`, but it choked on a layer that contained a symbolic link to a directory.
So, we implemented a directory hashing function in https://github.com/mboldt/lifecycle/blob/703-read-only-layers-perf/hasher.go.
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

This is implemented in a [lifecycle fork](https://github.com/mboldt/lifecycle/tree/703-read-only-layers-perf).

### Experiment

The [main.sh](main.sh) script builds the modified lifecycle.
The lifecycle code uses an environment variable `CNB_LIFECYCLE_RO_LAYERS` as a feature flag to enable the read-only layers detection.
It also measures and prints the duration of these checks to see how long they take.

For a builder, it uses [paketo-buildpacks/tiny-builder](https://github.com/paketo-buildpacks/tiny-builder) as a base, and injects the modified lifecycle.
It creates two versions of the builder: one with the feature flag set, and one without it.
If we want to run end-to-end comparisons, they are both available.

It uses [spring-petclinic/spring-petclinic-rest](https://github.com/spring-petclinic/spring-petclinic-rest) as the target application.

### Results

Running this experiment, the read-only layers check takes about 14s total time (1.7--1.9 seconds after each of 8 buildpacks), of a total build time of 27 seconds.
This nearly doubles the build time.

It did emit warnings about some of the buildpacks modifying layers which they did not create, but they were false positives.
The restorer restored these layers, and the modifying buildpacks actually do "own" them.
When building the image with `--clear-cache`, these warnings do not show up.

The current detection just looks for changes to existing layer directories.
We could, instead, count how many times a layer has changed post-restorer.
This improvement in detection would not greatly impact performance, so we do not plan to implement it for this spike.

## Approach 2: File System Watcher

For this approach, we used the [fsnotify library](https://github.com/fsnotify/fsnotify) to watch the layers directory (and all subdirectories) for changes.
It sets up a watcher for each buildpack separately, and aggregates the results into a list of buildpacks that have modified each layer.

This is implemented in a [lifecycle fork](https://github.com/mboldt/lifecycle/tree/703-read-only-layers-watcher).

### Experiment

The experimental approach is basically the same as in Hashing Layers.
The only difference is with measuring the performance impact.
Since the file system watcher is asynchronous and event-driven, it is not straight-forward to measure the impact on build time.
Instead, we simply measured the full runtime of the `pack build` command using `time(1)` over five runs, both with and without the watcher.

### Results

The file system watcher adds relatively little time to the build.
On average, it adds about 0.5 seconds to a 12-second build.

| Without watcher | With watcher |      |
|-----------------|--------------|------|
| 12.719          | 13.243       |      |
| 12.604          | 13.292       |      |
| 12.426          | 12.993       |      |
| 12.317          | 12.678       |      |
| 12.539          | 12.75        |      |
|-----------------|--------------|------|
| 12.521          | 12.9912      | Avg. |


## Conclusion and Next Steps

The file system watcher approach shows promise for efficiently detecting which buildpacks change which layers.
We could use this to detect and warn or error when multiple buildpacks modify the same layer.

With the performance impact of detecting layer changes better understood, we can bring this back to the discussion of the [read-only layers RFC](https://github.com/buildpacks/rfcs/pull/155).
