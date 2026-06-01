import 'package:flutter_test/flutter_test.dart';
import 'package:image_forge_core/image_forge_core.dart';

void main() {
  group('EditOp', () {
    group('filter variant', () {
      test('construction', () {
        final op = EditOp.filter(filter: ImageFilter.sharpen());
        expect(op, isA<EditOp_Filter>());
        final filter = (op as EditOp_Filter).filter;
        expect(filter, isA<ImageFilter_Sharpen>());
      });

      test('equality', () {
        final a = EditOp.filter(filter: ImageFilter.blur(radius: 5));
        final b = EditOp.filter(filter: ImageFilter.blur(radius: 5));
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    group('resize variant', () {
      test('construction', () {
        const op = EditOp.resize(
          width: 1920,
          height: 1080,
          algorithm: ResizeAlgorithm.lanczos3,
        );
        expect(op, isA<EditOp_Resize>());
        final resize = op as EditOp_Resize;
        expect(resize.width, 1920);
        expect(resize.height, 1080);
        expect(resize.algorithm, ResizeAlgorithm.lanczos3);
      });

      test('equality', () {
        const a = EditOp.resize(width: 100, height: 200, algorithm: ResizeAlgorithm.nearest);
        const b = EditOp.resize(width: 100, height: 200, algorithm: ResizeAlgorithm.nearest);
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    group('crop variant', () {
      test('construction', () {
        const op = EditOp.crop(x: 10, y: 20, width: 100, height: 200);
        expect(op, isA<EditOp_Crop>());
        final crop = op as EditOp_Crop;
        expect(crop.x, 10);
        expect(crop.y, 20);
        expect(crop.width, 100);
        expect(crop.height, 200);
      });

      test('equality', () {
        const a = EditOp.crop(x: 0, y: 0, width: 50, height: 50);
        const b = EditOp.crop(x: 0, y: 0, width: 50, height: 50);
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    group('rotate variant', () {
      test('construction', () {
        const op = EditOp.rotate(rotation: Rotation.rotate90);
        expect(op, isA<EditOp_Rotate>());
        expect((op as EditOp_Rotate).rotation, Rotation.rotate90);
      });

      test('equality', () {
        const a = EditOp.rotate(rotation: Rotation.flipHorizontal);
        const b = EditOp.rotate(rotation: Rotation.flipHorizontal);
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    test('different variants not equal', () {
      final a = EditOp.filter(filter: ImageFilter.sharpen());
      final b = EditOp.crop(x: 0, y: 0, width: 100, height: 100);
      expect(a, isNot(equals(b)));
    });

    test('when pattern matching', () {
      final op = EditOp.filter(filter: ImageFilter.blur(radius: 3));
      final result = op.when(
        filter: (f) => 'filter-${(f as ImageFilter_Blur).radius}',
        resize: (w, h, a) => 'resize-$w-$h',
        crop: (x, y, w, h) => 'crop-$x-$y',
        rotate: (r) => 'rotate-$r',
      );
      expect(result, 'filter-3');
    });

    test('map pattern matching', () {
      final op = EditOp.rotate(rotation: Rotation.rotate180);
      final result = op.map(
        filter: (_) => 'F',
        resize: (_) => 'R',
        crop: (_) => 'C',
        rotate: (_) => 'T',
      );
      expect(result, 'T');
    });

    test('maybeWhen returns value for matching variant', () {
      final op = EditOp.crop(x: 1, y: 2, width: 3, height: 4);
      final result = op.maybeWhen(
        crop: (x, y, w, h) => '$x,$y,$w,$h',
        orElse: () => 'other',
      );
      expect(result, '1,2,3,4');
    });

    test('maybeWhen returns orElse for non-matching variant', () {
      final op = EditOp.filter(filter: ImageFilter.sharpen());
      final result = op.maybeWhen(
        crop: (x, y, w, h) => '$x,$y',
        orElse: () => 'not-crop',
      );
      expect(result, 'not-crop');
    });

    test('maybeMap returns value for matching variant', () {
      final op = EditOp.rotate(rotation: Rotation.flipVertical);
      final result = op.maybeMap(
        rotate: (_) => 'rotated',
        orElse: () => 'other',
      );
      expect(result, 'rotated');
    });
  });
}
