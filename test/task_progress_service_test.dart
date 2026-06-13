import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:bitacora/services/task_progress_service.dart';
import 'package:bitacora/services/local_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TaskProgressService Tests', () {
    late FakeFirebaseFirestore firestore;
    late LocalCacheService cacheService;
    late TaskProgressService service;
    const userId = 'user-1';

    setUp(() async {
      await setUpTestHive();
      firestore = FakeFirebaseFirestore();
      cacheService = LocalCacheService();
      await cacheService.initialize();
      service = TaskProgressService.test(
        firestore: firestore,
        cache: cacheService,
      );
      await service.initialize();
    });

    tearDown(() async {
      await cacheService.dispose();
      await tearDownTestHive();
    });

    test('setProgress guarda en Hive y en Firestore', () async {
      await service.setProgress(
        userId,
        'task-1',
        isCompleted: true,
        isSubmitted: true,
      );

      final local = service.getProgress(userId, 'task-1');
      expect(local, {'isCompleted': true, 'isSubmitted': true});

      final remoteDoc = await firestore
          .collection('userProgress')
          .doc(userId)
          .collection('tasks')
          .doc('task-1')
          .get();
      expect(remoteDoc.exists, isTrue);
      expect(remoteDoc.data()!['isCompleted'], true);
      expect(remoteDoc.data()!['isSubmitted'], true);
    });

    test(
      'syncProgress sube progreso local que no existe remotamente',
      () async {
        await service.setProgress(
          userId,
          'task-local-only',
          isCompleted: true,
          isSubmitted: false,
        );

        await service.syncProgress(userId);

        final remoteDoc = await firestore
            .collection('userProgress')
            .doc(userId)
            .collection('tasks')
            .doc('task-local-only')
            .get();
        expect(remoteDoc.exists, isTrue);
        expect(remoteDoc.data()!['isCompleted'], true);
        expect(remoteDoc.data()!['isSubmitted'], false);
      },
    );

    test(
      'syncProgress descarga progreso remoto que no existe localmente',
      () async {
        await firestore
            .collection('userProgress')
            .doc(userId)
            .collection('tasks')
            .doc('task-remote-only')
            .set({
              'isCompleted': true,
              'isSubmitted': true,
              'updatedAt': DateTime.now().millisecondsSinceEpoch,
            });

        expect(service.getProgress(userId, 'task-remote-only'), isNull);

        await service.syncProgress(userId);

        final local = service.getProgress(userId, 'task-remote-only');
        expect(local, {'isCompleted': true, 'isSubmitted': true});
      },
    );

    test('syncProgress aplica last-write-wins según updatedAt', () async {
      // Progreso local "viejo".
      await service.setProgress(
        userId,
        'task-conflict',
        isCompleted: false,
        isSubmitted: false,
      );

      // Progreso remoto más reciente que el local.
      final newerTimestamp =
          DateTime.now().millisecondsSinceEpoch + 1000 * 60 * 60;
      await firestore
          .collection('userProgress')
          .doc(userId)
          .collection('tasks')
          .doc('task-conflict')
          .set({
            'isCompleted': true,
            'isSubmitted': true,
            'updatedAt': newerTimestamp,
          });

      await service.syncProgress(userId);

      final local = service.getProgress(userId, 'task-conflict');
      expect(local, {'isCompleted': true, 'isSubmitted': true});
    });

    test('pushProgress no falla si no hay progreso local', () async {
      await service.pushProgress(userId, 'nonexistent');
      final remoteDoc = await firestore
          .collection('userProgress')
          .doc(userId)
          .collection('tasks')
          .doc('nonexistent')
          .get();
      expect(remoteDoc.exists, isFalse);
    });
  });
}
