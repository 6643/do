# Generated WIT bindings

This directory is the project-local output of `do wit bind`. The generated
`.do` modules, `manifest.json`, and `wit.lock` are ordinary project files; WIT
sources belong in a separate `wit/src/` tree and are never read back as
generated input.

Regenerate from the repository root:

```bash
./bin/do wit bind examples/wit-bindgen-do/async-world.wit \
  --world probe --out examples/wit-bindgen-do/project/wit
```
