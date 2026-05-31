#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VtLinkMode {
    None,
    /// CVPixelBuffer / IOSurface frames passed decoder → encoder without CPU transfer.
    ZeroCopy,
    /// VTPixelTransferSession resize on GPU (no swscale).
    GpuScale,
}
