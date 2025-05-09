# ChunkCodecs Dev Notes

## Repository directories

This monorepo holds a number of different Julia packages:

- `ChunkCodecCore`: defines the interface.
- `ChunkCodecTests`: defines tests for the interface.
- `test`: contains slower compatibility tests.

There are also a number of packages with glue code to implement the interface for various C libraries and formats.

## Running basic tests

First install Julia 1.12 or later from <https://julialang.org/install/>.

Then instantiate the workspace:

```sh
julia --project=. -e 'import Pkg; Pkg.update()'
```

Each package contains basic tests in its `"test"` sub directory.

For example here is how to run the tests for `LibZlib`.

Run test script:

```sh
julia --project=LibZlib/test LibZlib/test/runtests.jl
```

If you are on a machine with more than 24 GB of RAM you can also run:

```sh
julia --project=LibZlib/test --heap-size-hint=15G LibZlib/test/big-mem-tests.jl
```

This will use local versions of other packages in this repo.

To test the package as it would be when installed:
copy the package to a temporary directory before testing.

```sh
julia -e 'mkdir("temp"); cp("LibZlib", "temp/LibZlib")'
julia --project=temp/LibZlib -e 'import Pkg; Pkg.update()'
julia --project=temp/LibZlib/test temp/LibZlib/test/runtests.jl
```

## Running compatibility tests

The main `"test"` directory contains more tests.
These tests have complex dependencies and are more fragile.

For example to run
[imagecodecs](https://github.com/cgohlke/imagecodecs) compatibility tests.

```sh
julia --project=test -e 'import Pkg; Pkg.update()'
julia --project=test test/imagecodecs-compat.jl
```

## Creating a new ChunkCodec package

Start by generating a new subdirectory package.

If the new package is wrapping a C library use the `Lib` prefix.

For example:

```julia-repl
julia> using Pkg; Pkg.generate("LibFoo")
```

Add this subdirectory to the "workspace" section of the root "Project.toml"

Add the package to the ".github/workflows/CI.yml" file

Adjust the new subdirectory to match the style of the existing subdirectories.
"LibBzip2" is a good example of a streaming format. "LibSnappy" is a good example
of a non streaming format.
