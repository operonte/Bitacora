import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:bitacora/services/sync_service.dart';
import 'package:bitacora/services/local_cache_service.dart';
import 'package:bitacora/firebase_service.dart';
import 'package:bitacora/task_model.dart';
import 'package:bitacora/subject_model.dart';

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
      syncService = SyncService.test(
        cache: mockCache,
        firebase: mockFirebase,
      );
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
      
      test('syncs pending tasks on reconnection', () async {
        // Simulate offline task creation
        final pendingTask = [
          {
            'type': 'task',
            'id': 'temp_task_123',
            'operation': 'create',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }
        ];
        
        when(mockCache.getPendingSync()).thenReturn(pendingTask);
        when(mockCache.getCachedTask('temp_task_123')).thenReturn(
          Task(
            id: 'temp_task_123',
            title: 'Offline Task',
            subject: 'Test',
            professor: 'Test',
            dueDate: DateTime.now(),
            type: 'trabajo',
            userId: 'user-123',
            userName: 'Test User',
          ),
        );
        
        when(mockFirebase.addTask(any)).thenAnswer((_) async => 'real_task_id_456');
        when(mockCache.cacheTask(any)).thenAnswer((_) async {});
        when(mockCache.removeCachedTask(any)).thenAnswer((_) async {});
        
        // Trigger sync
        final result = await syncService.forceSync();
        
        expect(result, SyncResult.success);
        verify(mockFirebase.addTask(any)).called(1);
      });
      
      test('hasPendingChanges returns true with pending items', () {
        when(mockCache.getPendingSync()).thenReturn([
          {'type': 'task', 'id': '1', 'operation': 'create'},
        ]);
        
        expect(syncService.hasPendingChanges(), true);
      });
      
      test('pendingChangesCount returns correct number', () {
        when(mockCache.getPendingSync()).thenReturn([
          {'type': 'task', 'id': '1', 'operation': 'create'},
          {'type': 'task', 'id': '2', 'operation': 'update'},
        ]);
        
        expect(syncService.pendingChangesCount, 2);
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
