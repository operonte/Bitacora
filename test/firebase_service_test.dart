import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:bitacora/firebase_service.dart';
import 'package:bitacora/task_model.dart';
import 'package:bitacora/subject_model.dart';

void main() {
  group('FirebaseService Tests', () {
    late FirebaseService firebaseService;
    late FakeFirebaseFirestore fakeFirestore;
    late MockFirebaseAuth mockAuth;
    
    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      mockAuth = MockFirebaseAuth(mockUser: MockUser(
        uid: 'test-user-123',
        email: 'test@test.com',
        displayName: 'Test User',
      ));
      
      firebaseService = FirebaseService.test(
        firestore: fakeFirestore,
        auth: mockAuth,
      );
    });
    
    group('Task Operations', () {
      test('addTask creates task in Firestore', () async {
        final task = Task(
          title: 'Test Task',
          description: 'Test Description',
          subject: 'Test Subject',
          professor: 'Test Professor',
          dueDate: DateTime.now(),
          type: 'trabajo',
          userId: 'test-user-123',
          userName: 'Test User',
          createdAt: DateTime.now(),
        );
        
        final id = await firebaseService.addTask(task);
        
        expect(id, isNotNull);
        expect(id.isNotEmpty, true);
        
        // Verify in Firestore
        final snapshot = await fakeFirestore
            .collection('dtbitacora')
            .doc('test-user-123')
            .collection('tasks')
            .doc(id)
            .get();
        
        expect(snapshot.exists, true);
        expect(snapshot.data()?['title'], 'Test Task');
      });
      
      test('getTasks returns list of tasks', () async {
        // Add test tasks
        await firebaseService.addTask(Task(
          title: 'Task 1',
          description: 'Description 1',
          subject: 'Subject 1',
          professor: 'Prof 1',
          dueDate: DateTime.now(),
          type: 'trabajo',
          userId: 'test-user-123',
          userName: 'Test User',
          createdAt: DateTime.now(),
        ));
        
        await firebaseService.addTask(Task(
          title: 'Task 2',
          description: 'Description 2',
          subject: 'Subject 2',
          professor: 'Prof 2',
          dueDate: DateTime.now(),
          type: 'examen',
          userId: 'test-user-123',
          userName: 'Test User',
          createdAt: DateTime.now(),
        ));
        
        final tasks = await firebaseService.getTasks();
        
        expect(tasks.length, 2);
        expect(tasks.any((t) => t.title == 'Task 1'), true);
        expect(tasks.any((t) => t.title == 'Task 2'), true);
      });
      
      test('updateTask modifies existing task', () async {
        final task = Task(
          title: 'Original Title',
          subject: 'Test Subject',
          professor: 'Test Professor',
          dueDate: DateTime.now(),
          type: 'trabajo',
          userId: 'test-user-123',
          userName: 'Test User',
        );
        
        final id = await firebaseService.addTask(task);
        
        final updatedTask = Task(
          id: id,
          title: 'Updated Title',
          subject: 'Test Subject',
          professor: 'Test Professor',
          dueDate: DateTime.now(),
          type: 'trabajo',
          userId: 'test-user-123',
          userName: 'Test User',
        );
        
        await firebaseService.updateTask(updatedTask);
        
        // Verify update
        final snapshot = await fakeFirestore
            .collection('dtbitacora')
            .doc('test-user-123')
            .collection('tasks')
            .doc(id)
            .get();
        
        expect(snapshot.data()?['title'], 'Updated Title');
      });
      
      test('deleteTask removes task from Firestore', () async {
        final task = Task(
          title: 'Task to Delete',
          subject: 'Test Subject',
          professor: 'Test Professor',
          dueDate: DateTime.now(),
          type: 'trabajo',
          userId: 'test-user-123',
          userName: 'Test User',
        );
        
        final id = await firebaseService.addTask(task);
        await firebaseService.deleteTask(id);
        
        // Verify deletion
        final snapshot = await fakeFirestore
            .collection('dtbitacora')
            .doc('test-user-123')
            .collection('tasks')
            .doc(id)
            .get();
        
        expect(snapshot.exists, false);
      });
    });
    
    group('Subject Operations', () {
      test('addSubject creates subject in Firestore', () async {
        final subject = Subject(
          name: 'Test Subject',
          professor: 'Test Professor',
          visibility: SubjectVisibility.soloYo,
          userId: 'test-user-123',
          userName: 'Test User',
          createdAt: DateTime.now(),
        );
        
        final id = await firebaseService.addSubject(subject);
        
        expect(id, isNotNull);
        
        final snapshot = await fakeFirestore
            .collection('dtbitacora')
            .doc('test-user-123')
            .collection('subjects')
            .doc(id)
            .get();
        
        expect(snapshot.exists, true);
        expect(snapshot.data()?['name'], 'Test Subject');
      });
      
      test('getSubjects returns ordered list', () async {
        await firebaseService.addSubject(Subject(
          name: 'Zebra',
          professor: 'Prof Z',
          visibility: SubjectVisibility.soloYo,
          userId: 'test-user-123',
          userName: 'Test User',
          createdAt: DateTime.now(),
        ));
        
        await firebaseService.addSubject(Subject(
          name: 'Apple',
          professor: 'Prof A',
          visibility: SubjectVisibility.cursoCompleto,
          userId: 'test-user-123',
          userName: 'Test User',
          createdAt: DateTime.now(),
        ));
        
        final subjects = await firebaseService.getSubjects();
        
        expect(subjects.length, 2);
        expect(subjects[0].name, 'Apple'); // Ordered alphabetically
        expect(subjects[1].name, 'Zebra');
      });
    });
    
    group('Filtering', () {
      test('getPendingTasks returns only future non-delivered tasks', () async {
        final now = DateTime.now();
        
        // Pending task (future, not delivered)
        await firebaseService.addTask(Task(
          title: 'Pending Task',
          subject: 'Test',
          professor: 'Test',
          dueDate: now.add(Duration(days: 7)),
          isCompleted: false,
          isSubmitted: false,
          type: 'trabajo',
          userId: 'test-user-123',
          userName: 'Test User',
        ));
        
        // Overdue task (past)
        await firebaseService.addTask(Task(
          title: 'Overdue Task',
          subject: 'Test',
          professor: 'Test',
          dueDate: now.subtract(Duration(days: 1)),
          isCompleted: false,
          isSubmitted: false,
          type: 'trabajo',
          userId: 'test-user-123',
          userName: 'Test User',
        ));
        
        // Delivered task
        await firebaseService.addTask(Task(
          title: 'Delivered Task',
          subject: 'Test',
          professor: 'Test',
          dueDate: now.add(Duration(days: 7)),
          isCompleted: true,
          isSubmitted: true,
          type: 'trabajo',
          userId: 'test-user-123',
          userName: 'Test User',
        ));
        
        final pending = await firebaseService.getPendingTasks();
        
        expect(pending.length, 1);
        expect(pending[0].title, 'Pending Task');
      });
    });
  });
}
