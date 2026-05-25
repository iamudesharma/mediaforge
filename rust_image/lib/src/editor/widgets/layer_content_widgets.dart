import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/overlay_layer.dart';
import '../services/shape_paths.dart';
import '../services/sticker_catalog.dart';
import '../services/sticker_image_cache.dart';
import '../theme/lumina_tokens.dart';

class LayerContentWidget extends StatelessWidget {
  const LayerContentWidget({super.key, required this.layer});

  final OverlayLayer layer;

  @override
  Widget build(BuildContext context) {
    return switch (layer) {
      EmojiLayer(:final glyph, :final fontSize) => FittedBox(
          fit: BoxFit.contain,
          child: Text(
            glyph,
            style: TextStyle(fontSize: fontSize),
          ),
        ),
      TextLayer(
        :final text,
        :final fontSize,
        :final color,
        :final backgroundStyle,
        :final backgroundColor,
        :final padding,
        :final cornerRadius,
      ) =>
        FittedBox(
          fit: BoxFit.contain,
          child: Container(
            padding: EdgeInsets.all(padding),
            decoration: backgroundStyle == TextBackgroundStyle.none
                ? null
                : BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(cornerRadius),
                  ),
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      StickerLayer sticker => _StickerLayerImage(layer: sticker),
      _ => const SizedBox.shrink(),
    };
  }
}

class _StickerLayerImage extends StatelessWidget {
  const _StickerLayerImage({required this.layer});

  final StickerLayer layer;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 120.0;
        final h = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : 120.0;

        Widget image;
        if (layer.userBytes != null && layer.userBytes!.isNotEmpty) {
          image = _UserStickerImage(
            bytes: layer.userBytes!,
            width: w,
            height: h,
          );
        } else if (layer.cachedWidth > 0 && layer.cachedPixels != null) {
          image = Image.memory(
            layer.cachedPixels!,
            width: w,
            height: h,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          );
        } else if (layer.assetKey != null) {
          image = SizedBox(
            width: w,
            height: h,
            child: _BuiltinStickerImage(assetKey: layer.assetKey!),
          );
        } else {
          return const SizedBox.shrink();
        }

        if (layer.shapeMask == StickerShapeMask.none) {
          return SizedBox(width: w, height: h, child: image);
        }

        return SizedBox(
          width: w,
          height: h,
          child: ClipPath(
            clipper: _ShapeMaskClipper(
              mask: layer.shapeMask,
              width: w,
              height: h,
              cornerRadius: layer.maskCornerRadius,
            ),
            child: image,
          ),
        );
      },
    );
  }
}

class _ShapeMaskClipper extends CustomClipper<Path> {
  _ShapeMaskClipper({
    required this.mask,
    required this.width,
    required this.height,
    required this.cornerRadius,
  });

  final StickerShapeMask mask;
  final double width;
  final double height;
  final double cornerRadius;

  @override
  Path getClip(Size size) {
    return ShapePaths.build(
      mask,
      width: width,
      height: height,
      cornerRadius: cornerRadius,
    );
  }

  @override
  bool shouldReclip(covariant _ShapeMaskClipper old) =>
      old.mask != mask ||
      old.width != width ||
      old.height != height ||
      old.cornerRadius != cornerRadius;
}

class _UserStickerImage extends StatelessWidget {
  const _UserStickerImage({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.Image>(
      future: StickerImageCache.imageFor(bytes),
      builder: (context, snapshot) {
        final img = snapshot.data;
        if (img == null) {
          return SizedBox(width: width, height: height);
        }
        return RawImage(
          image: img,
          width: width,
          height: height,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        );
      },
    );
  }
}

class _BuiltinStickerImage extends StatelessWidget {
  const _BuiltinStickerImage({required this.assetKey});

  final String assetKey;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      StickerCatalog.assetPath(assetKey),
      package: StickerCatalog.assetPackage,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) => Icon(
        _iconForKey(assetKey),
        size: 48,
        color: LuminaTokens.primary,
      ),
    );
  }

  IconData _iconForKey(String key) => switch (key) {
        'heart' => Icons.favorite,
        'star' => Icons.star,
        'arrow' => Icons.arrow_forward,
        'chat' => Icons.chat_bubble,
        'bolt' => Icons.bolt,
        'check' => Icons.check_circle,
        'circle' => Icons.circle_outlined,
        'square' => Icons.crop_square,
        'triangle' => Icons.change_history,
        'spark' => Icons.auto_awesome,
        'flag' => Icons.flag,
        'music' => Icons.music_note,
        'camera' => Icons.camera_alt,
        'gift' => Icons.card_giftcard,
        'fire' => Icons.local_fire_department,
        'cloud' => Icons.cloud,
        'sun' => Icons.wb_sunny,
        'moon' => Icons.nightlight_round,
        'leaf' => Icons.eco,
        'wave' => Icons.waves,
        'pin' => Icons.push_pin,
        'tag' => Icons.sell,
        'bell' => Icons.notifications,
        'book' => Icons.menu_book,
        _ => Icons.star,
      };
}
