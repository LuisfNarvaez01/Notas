import 'package:flutter_test/flutter_test.dart';
import 'package:hilva/services/update_service.dart';

void main() {
  test(
    'release comparisons preserve numeric ordering and ignore build metadata',
    () {
      expect(UpdateService.isNewer('v1.10.0', '1.9.9'), isTrue);
      expect(UpdateService.isNewer('v2.0.0', '1.99.99'), isTrue);
      expect(UpdateService.isNewer('v1.0.0', '1.0.0+2'), isFalse);
      expect(UpdateService.isNewer('v0.9.0', '1.0.0'), isFalse);
    },
  );
}
