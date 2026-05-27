/// Curated emoji grid + built-in sticker asset keys under [assets/stickers/].
abstract final class StickerCatalog {
  static const emojis = [
    '😀', '😂', '🥰', '😎', '🤩', '😍', '🥳', '😭',
    '👍', '👎', '✌️', '🤞', '👏', '🙌', '💪', '🤝',
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍',
    '🔥', '⭐', '✨', '💯', '🎉', '🎊', '🏆', '⚡',
    '🌈', '☀️', '🌙', '⭐', '🌸', '🍕', '🍔', '☕',
    '🐶', '🐱', '🦊', '🐻', '🦁', '🐸', '🦄', '🐝',
    '🚗', '✈️', '🚀', '🎸', '📷', '💡', '🎁', '💎',
  ];

  static const builtinStickers = [
    ('heart', 'Heart'),
    ('star', 'Star'),
    ('arrow', 'Arrow'),
    ('chat', 'Chat'),
    ('bolt', 'Bolt'),
    ('check', 'Check'),
    ('circle', 'Circle'),
    ('square', 'Square'),
    ('triangle', 'Triangle'),
    ('spark', 'Spark'),
    ('flag', 'Flag'),
    ('music', 'Music'),
    ('camera', 'Camera'),
    ('gift', 'Gift'),
    ('fire', 'Fire'),
    ('cloud', 'Cloud'),
    ('sun', 'Sun'),
    ('moon', 'Moon'),
    ('leaf', 'Leaf'),
    ('wave', 'Wave'),
    ('pin', 'Pin'),
    ('tag', 'Tag'),
    ('bell', 'Bell'),
    ('book', 'Book'),
  ];

  /// Path for [Image.asset] / [rootBundle] — always use `package: rust_image`.
  static const assetPackage = 'rust_image_editor';

  static String assetPath(String key) => 'assets/stickers/$key.png';
}
