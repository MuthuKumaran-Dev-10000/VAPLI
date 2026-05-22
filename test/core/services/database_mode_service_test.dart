import 'package:flutter_test/flutter_test.dart';
import 'package:lubrication_indicator/core/services/database_mode_service.dart';

void main() {
  group('DatabaseModeService.path', () {
    test('uses production path when development mode is false', () {
      DatabaseModeService.isDevelopment.value = false;
      expect(DatabaseModeService.path('tanks/123'), 'tanks/123');
      expect(DatabaseModeService.path('/users'), 'users');
      expect(DatabaseModeService.path(''), '');
    });

    test('prefixes testDB when development mode is true', () {
      DatabaseModeService.isDevelopment.value = true;
      expect(DatabaseModeService.path('tanks/123'), 'testDB/tanks/123');
      expect(DatabaseModeService.path('/users'), 'testDB/users');
      expect(DatabaseModeService.path(''), 'testDB');
    });
  });
}

