import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image_forge_editor/image_forge_editor.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustImageEditor.ensureInitialized();
  });

  test('Rust bridge initializes', () async {
    expect(RustImageEditor.ensureInitialized, isNotNull);
  });
}
