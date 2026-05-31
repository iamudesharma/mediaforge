/// Layout insets for the mobile immersive canvas (preview + floating controls).
class MobileChromeMetrics {
  const MobileChromeMetrics({
    this.topInset = 0,
    this.bottomInset = 0,
    this.stripHeight = 0,
    this.sheetHeight = 0,
  });

  final double topInset;
  final double bottomInset;
  final double stripHeight;
  final double sheetHeight;

  static const zero = MobileChromeMetrics();

  MobileChromeMetrics copyWith({
    double? topInset,
    double? bottomInset,
    double? stripHeight,
    double? sheetHeight,
  }) {
    return MobileChromeMetrics(
      topInset: topInset ?? this.topInset,
      bottomInset: bottomInset ?? this.bottomInset,
      stripHeight: stripHeight ?? this.stripHeight,
      sheetHeight: sheetHeight ?? this.sheetHeight,
    );
  }
}
