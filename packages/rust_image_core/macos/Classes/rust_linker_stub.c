// Keeps flutter_rust_bridge entry symbols linked into the app binary for
// ExternalLibrary.process() / dlsym(RTLD_DEFAULT, ...).
// Release builds strip unreferenced symbols unless force_load + -Wl,-u,... apply.
#include <stdint.h>

int64_t frb_get_rust_content_hash(void);

/// Called from RustImagePlugin.register so Swift references Rust (not stripped).
int64_t rust_image_link_rust_for_frb(void) {
  return frb_get_rust_content_hash();
}

__attribute__((used, constructor))
static void rust_image_force_link_rust(void) {
  (void)rust_image_link_rust_for_frb();
}
