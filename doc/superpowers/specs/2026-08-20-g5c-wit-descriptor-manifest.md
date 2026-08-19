# G5c WIT Descriptor Manifest

## Status

Design gate for the B route after the fixed WASI random A gate. This document
defines descriptor provenance and admission rules; it does not authorize the
default `do build` host/WIT route or the global GC cutover.

## Goal

Make every GC host/WIT marshal plan derive its WIT identity, source bytes,
signature, and canonical import from one checked-in descriptor manifest. A
caller may select a descriptor by stable key, but may not provide a second
source, signature, layout identity, or import name that can drift from it.

## Manifest

The first manifest is `doc/wit/gc_descriptor_manifest.json` and uses schema 1:

```json
{
  "schema": 1,
  "toolchain": "wasm-tools 1.255.0",
  "descriptors": [
    {
      "id": "wasi:random/random.get-random-bytes@0.3.0-rc-2025-09-16/lift",
      "source": "src/build/p3_wit/.../deps/random/random.wit",
      "world_source": "src/build/p3_wit/.../deps/random/world.wit",
      "package": "wasi:random@0.3.0-rc-2025-09-16",
      "world": "imports",
      "interface": "random",
      "member": "get-random-bytes",
      "direction": "lift",
      "params": ["u64"],
      "result": "list<u8>",
      "source_sha256": "sha256:<64 lowercase hex digits>",
      "canonical_import": {
        "module": "wasi:random/random@0.3.0-rc-2025-09-16",
        "name": "get-random-bytes"
      }
    }
  ]
}
```

`source` and `world_source` are repository-relative, normalized paths. The
hash is computed over the exact concatenated WIT bytes supplied to the parser
by the loader, with an explicit single-byte newline separator. The manifest
stores the resolved package/version and member signature as claims; the loader
must compare them with the parser result rather than trusting the JSON.

The current parser-backed concatenation contract admits one package declaration
per descriptor input. `world_source` therefore names a package-less world
fragment (or another source fragment that does not repeat `package`); a raw
second package declaration fails before marshal planning. Supporting raw
multi-file package concatenation requires a separate resolver change and is not
part of this gate.

## Admission Rules

1. The manifest schema, toolchain floor, descriptor id, paths, direction, and
   SHA-256 format are validated before any WAT is emitted.
2. Source paths must remain inside the repository root and must not contain
   absolute components or `..` traversal.
3. The loader reads both source files, computes the declared hash, resolves the
   requested world/member, and compares package, world, interface, member,
   params, result, and direction with the manifest entry.
4. The canonical Component import is derived from the resolved WIT package and
   version. A manifest import claim that differs from the derived import is a
   hard error.
5. Unknown ids, duplicate ids, missing files, hash drift, package/version
   drift, signature drift, world/member drift, and unsupported WIT shapes fail
   closed before marshal planning.
6. Only the existing synchronous value-only marshal shapes are eligible. The
   manifest does not admit resources, `option`, `result`, variants, tuples,
   future/stream, async functions, or arbitrary producer expressions.
7. The `cm32p2|wasi:*` names remain legacy host-core lowering facts. They are
   not substituted for the versioned WIT canonical import in this manifest.

## Ownership and API Boundary

The descriptor loader owns source buffers and the parsed `BindingModel` for one
request. The marshal route receives a validated descriptor plan and measured
layout facts; it cannot receive an independent `DescriptorIdentity` or caller
source. `wit` modules do not import compiler/codegen modules.

## Failure Contract

All manifest, source, resolver, signature, hash, and canonical-import drift is
reported as a named error. No error path falls back to the ARC host/WIT route,
and no partially resolved descriptor is cached or emitted.

## Gates

- Focused Zig parser/loader tests cover valid random descriptor, duplicate id,
  path escape, source hash drift, signature drift, and unknown id.
- The A shell gate is migrated to load the descriptor instead of passing WIT
  source directly.
- A negative assembly test mutates the WIT member or source and must fail
  before `wasm-tools component new`.
- The default compiler route remains ARC-backed until this manifest gate, the
  host/WIT inventory, and same-fixture ARC/GC equivalence are complete.
