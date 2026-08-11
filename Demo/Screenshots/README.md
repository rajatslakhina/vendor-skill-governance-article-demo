# Screenshots

Intentionally empty.

The run that produced this repository was an unattended scheduled task. Screen-control
approval cannot be granted with nobody present to approve it, so `Demo.xcodeproj` was
never launched on a Simulator and no screenshot was captured.

The library itself is verified: `swift build` is clean and `swift test` runs 20 tests
with 0 failures. The project file was checked structurally (balanced braces and parens,
every object id defined, no dangling references) and is byte-identical — modulo the
module name and bundle identifier — to a project file previously confirmed to build and
launch on Simulator.

A placeholder image would have been dishonest, so there isn't one.
