# Native build hook (optional)

For Flutter native assets / `native_toolchain_rust`, restore `hook/build.dart` using the template in [docs/setup.md](../../docs/setup.md).

Default builds use:

- **Desktop:** Corrosion via `src/CMakeLists.txt`
- **Mobile CI:** `tools/release/package-*.sh`
- **Local dev:** `cargo build --release -p video_processor_core`
