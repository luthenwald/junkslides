# Zeno. Run `just --list` for recipes.

default:
   @just --list

# Core: unit tests and the laws as properties, on both targets
core-test:
   cd core && gleam test --target erlang && gleam test --target javascript

# Everything that is not a spike
test: core-test

# S5: jot coverage and the block splitter, on both targets
s5:
   cd spikes/s5_jot && gleam test --target erlang && gleam test --target javascript

# S4: watching, own-write detection, atomic writes (about 75 s)
s4:
   cd spikes/s4_files && gleam test

# S3: shared codec on both targets and the server round trip
s3-test:
   cd spikes/s3_socket/shared && gleam test --target erlang && gleam test --target javascript
   cd spikes/s3_socket/server && gleam test

# S3: build the client and serve it on http://127.0.0.1:4870
s3:
   cd spikes/s3_socket/client && gleam run -m lustre/dev build
   cd spikes/s3_socket/server && gleam run

chrome := env("HOME") / "Library/Caches/zeno-cft/156/chrome-headless-shell-mac-arm64/chrome-headless-shell"

# Build the S1 and S2 pages and the S3 client
browser-build:
   cd spikes/s1_drag && gleam run -m lustre/dev build
   cd spikes/s2_measure && gleam run -m lustre/dev build
   cd spikes/s3_socket/client && gleam run -m lustre/dev build

# S1 to S3 in headless Chrome for Testing, driven over CDP from Gleam
browser-test: browser-build
   #!/usr/bin/env bash
   set -u
   profile=$(mktemp -d)
   "{{chrome}}" --remote-debugging-port=9333 --user-data-dir="$profile" --no-first-run about:blank >/dev/null 2>&1 &
   pid=$!
   trap 'kill $pid; rm -rf "$profile"' EXIT
   sleep 1
   cd spikes/browser && gleam test

# All headless spike checks
spikes-test: s5 s3-test s4 browser-test
