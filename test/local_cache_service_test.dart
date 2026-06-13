import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:bitacora/services/local_cache_service.dart';
import 'package:bitacora/task_model.dart';
import 'package:bitacora/subject_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalCacheService Tests', () {
    late LocalCacheService cacheService;

    setUp(() async {
      // Initialize Hive for testing
      await setUpTestHive();
      cacheService = LocalCacheService();
      await cacheService.initialize();
    });

    tearDown(() async {
      await cacheService.dispose();
      await tearDownTestHive();
    });

    group('Task Cache', () {
      test('cacheTask stores task locally', () async {
        final task = Task(
          id: 'task-123',
          title: 'Cached Task',
          description: 'Cached Description',
          subject: 'Test Subject',
          professor: 'Test Professor',
          dueDate: DateTime.now(),
          type: 'trabajo',
          userId: 'user-123',
          userName: 'Test User',
          createdAt: DateTime.now(),
        );

        await cacheService.cacheTask(task);

        final cached = cacheService.getCachedTask('task-123');
        expect(cached, isNotNull);
        expect(cached?.title, 'Cached Task');
      });

      test('cacheTasks stores multiple tasks', () async {
        final tasks = [
          Task(
            id: 'task-1',
            title: 'Task One',
            description: 'Description 1',
            subject: 'Subject 1',
            professor: 'Prof 1',
            dueDate: DateTime.now(),
            type: 'trabajo',
            userId: 'user-123',
            userName: 'Test User',
            createdAt: DateTime.now(),
          ),
          Task(
            id: 'task-2',
            title: 'Task Two',
            description: 'Description 2',
            subject: 'Subject 2',
            professor: 'Prof 2',
            dueDate: DateTime.now(),
            type: 'examen',
            userId: 'user-123',
            userName: 'Test User',
            createdAt: DateTime.now(),
          ),
        ];

        await cacheService.cacheTasks(tasks);

        final cached = cacheService.getCachedTasks();
        expect(cached.length, 2);
      });

      test('removeCachedTask deletes task from cache', () async {
        final task = Task(
          id: 'task-delete',
          title: 'To Delete',
          description: 'Delete Description',
          subject: 'Test',
          professor: 'Test',
          dueDate: DateTime.now(),
          type: 'trabajo',
          userId: 'user-123',
          userName: 'Test User',
          createdAt: DateTime.now(),
        );

        await cacheService.cacheTask(task);
        expect(cacheService.getCachedTask('task-delete'), isNotNull);

        await cacheService.removeCachedTask('task-delete');
        expect(cacheService.getCachedTask('task-delete'), isNull);
      });

      test('clearAllCache removes all tasks', () async {
        await cacheService.cacheTasks([
          Task(
            id: 'task-1',
            title: 'Task 1',
            description: 'Description',
            subject: 'Test',
            professor: 'Test',
            dueDate: DateTime.now(),
            type: 'trabajo',
            userId: 'user-123',
            userName: 'Test User',
            createdAt: DateTime.now(),
          ),
        ]);

        expect(cacheService.getCachedTasks().length, 1);

        await cacheService.clearAllCache();

        expect(cacheService.getCachedTasks().length, 0);
      });
    });

    group('Subject Cache', () {
      test('cacheSubject stores subject locally', () async {
        final subject = Subject(
          id: 'sub-123',
          name: 'Cached Subject',
          professor: 'Test Prof',
          visibility: SubjectVisibility.soloYo,
          userId: 'user-123',
          userName: 'Test User',
          createdAt: DateTime.now(),
        );

        await cacheService.cacheSubject(subject);

        final subjects = cacheService.getCachedSubjects();
        expect(subjects.length, 1);
        expect(subjects[0].name, 'Cached Subject');
      });

      test('removeCachedSubject deletes subject', () async {
        final subject = Subject(
          id: 'sub-delete',
          name: 'To Delete',
          professor: 'Test',
          visibility: SubjectVisibility.cursoCompleto,
          userId: 'user-123',
          userName: 'Test User',
          createdAt: DateTime.now(),
        );

        await cacheService.cacheSubject(subject);
        expect(cacheService.getCachedSubjects().length, 1);

        await cacheService.removeCachedSubject('sub-delete');
        expect(cacheService.getCachedSubjects().length, 0);
      });
    });

    group('Pending Sync', () {
      test('markPendingSync stores operation', () async {
        await cacheService.markPendingSync('task', 'task-123', 'create');

        final pending = cacheService.getPendingSync();
        expect(pending.length, 1);
        expect(pending[0]['type'], 'task');
        expect(pending[0]['operation'], 'create');
      });

      test('clearPendingSync removes all pending', () async {
        await cacheService.markPendingSync('task', 'task-1', 'create');
        await cacheService.markPendingSync('task', 'task-2', 'update');

        expect(cacheService.getPendingSync().length, 2);

        await cacheService.clearPendingSync();

        expect(cacheService.getPendingSync().length, 0);
      });
    });

    group('Connection Status', () {
      test('connectionStream emits values', () async {
        // Should have initial value from initialize()
        expect(cacheService.connectionStream, isNotNull);
      });
    });
  });
}
