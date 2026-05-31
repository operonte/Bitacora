import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:bitacora/services/sync_service.dart';
import 'package:bitacora/services/local_cache_service.dart';
import 'package:bitacora/firebase_service.dart';

// Mocks
class MockLocalCacheService extends Mock implements LocalCacheService {}

class MockFirebaseService extends Mock implements FirebaseService {}

@GenerateMocks([LocalCacheService, FirebaseService])
void main() {
  group('SyncService Tests', () {
    late SyncService syncService;
    late MockLocalCacheService mockCache;
    late MockFirebaseService mockFirebase;

    setUp(() {
      mockCache = MockLocalCacheService();
      mockFirebase = MockFirebaseService();

      // Inject mocks using test constructor
      syncService = SyncService.test(cache: mockCache, firebase: mockFirebase);
    });

    group('Sync Operations', () {
      test('forceSync returns noConnection when offline', () async {
        when(mockCache.hasConnection()).thenAnswer((_) async => false);

        final result = await syncService.forceSync();

        expect(result, SyncResult.noConnection);
      });

      test('forceSync returns nothingToSync when no pending', () async {
        when(mockCache.hasConnection()).thenAnswer((_) async => true);
        when(mockCache.getPendingSync()).thenReturn([]);

        final result = await syncService.forceSync();

        expect(result, SyncResult.nothingToSync);
      });
    });

    group('Status Stream', () {
      test('emits syncing and completed on successful sync', () async {
        when(mockCache.hasConnection()).thenAnswer((_) async => true);
        when(mockCache.getPendingSync()).thenReturn([]);

        final statusHistory = <SyncStatus>[];
        syncService.statusStream.listen((status) {
          statusHistory.add(status);
        });

        await syncService.forceSync();

        expect(statusHistory, contains(SyncStatus.syncing));
        expect(statusHistory, contains(SyncStatus.completed));
      });
    });
  });
}
