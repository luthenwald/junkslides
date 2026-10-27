# Zeno. Run `just --list` for recipes.

default:
   @just --list

# S5: jot coverage and the block splitter, on both targets
s5:
   cd spikes/s5_jot && gleam test --target erlang && gleam test --target javascript

# All headless spike checks
spikes-test: s5
