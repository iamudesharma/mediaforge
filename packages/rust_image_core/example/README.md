# rust_image_core example

Minimal app: build a synthetic RGBA buffer, run `filterRgbaBuffer` (brightness), encode JPEG — **no** `rust_image_editor` or `GpuTextureView`.

## Run

From monorepo root (build Rust once):

```bash
dart pub get && dart run melos bootstrap
cd packages/rust_image_core/rust && cargo build --features gpu
cd ../example
flutter run -d macos   # or ios / android
```

If the test runner cannot link the plugin, point at a built dylib:

```bash
export RUST_IMAGE_DYLIB="$(pwd)/../rust/target/debug/librust_image_core.dylib"
flutter run -d macos
```

## CLI alternative (no Flutter)

```bash
cd packages/rust_image_core/rust
cargo run --release --features gpu --bin rust_image_benchmark -- \
  --synthetic -n 3 --only filter_rgba_brightness
```

See [docs/P0_ACCEPTANCE.md](../../../docs/P0_ACCEPTANCE.md) for the full pre-publish checklist.
