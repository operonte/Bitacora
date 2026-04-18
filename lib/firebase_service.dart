import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'task_model.dart';
import 'subject_model.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'dtbitacora',
  );
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleAuthProvider googleProvider = GoogleAuthProvider();
      return await _auth.signInWithProvider(googleProvider);
    } catch (e) {
      print('Error signing in with Google: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  CollectionReference get tasksCollection {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Usuario no autenticado');
    return _firestore.collection('dtbitacora').doc(user.uid).collection('tasks');
  }

  CollectionReference get subjectsCollection {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Usuario no autenticado');
    return _firestore.collection('dtbitacora').doc(user.uid).collection('subjects');
  }

  Future<String> addTask(Task task) async {
    final taskData = task.toMap();
    final docRef = await tasksCollection.add(taskData);
    return docRef.id;
  }

  Future<void> updateTask(Task task) async {
    if (task.id == null) throw Exception('Task ID is required for update');
    await tasksCollection.doc(task.id).update(task.toMap());
  }

  Future<void> deleteTask(String taskId) async {
    await tasksCollection.doc(taskId).delete();
  }

  Future<List<Task>> getTasks() async {
    final snapshot = await tasksCollection
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => Task.fromMap(doc.data() as Map<String, dynamic>, doc.id))
        .toList();
  }

  Future<List<Task>> getPendingTasks() async {
    final snapshot = await tasksCollection
        .orderBy('dueDate')
        .get();
    final tasks = snapshot.docs
        .map((doc) => Task.fromMap(doc.data() as Map<String, dynamic>, doc.id))
        .toList();
    // Filtrar: no entregadas (ambos true) Y fecha futura
    return tasks.where((task) {
      final isDelivered = task.isCompleted && task.isSubmitted;
      final isFuture = task.dueDate.isAfter(DateTime.now());
      return !isDelivered && isFuture;
    }).toList();
  }

  Future<List<Task>> getOverdueTasks() async {
    final snapshot = await tasksCollection
        .orderBy('dueDate', descending: true)
        .get();
    final tasks = snapshot.docs
        .map((doc) => Task.fromMap(doc.data() as Map<String, dynamic>, doc.id))
        .toList();
    // Filtrar: no entregadas (ambos true) Y fecha pasada
    return tasks.where((task) {
      final isDelivered = task.isCompleted && task.isSubmitted;
      final isPast = task.dueDate.isBefore(DateTime.now());
      return !isDelivered && isPast;
    }).toList();
  }

  Future<List<Task>> getDeliveredTasks() async {
    final snapshot = await tasksCollection
        .orderBy('dueDate', descending: true)
        .get();
    final tasks = snapshot.docs
        .map((doc) => Task.fromMap(doc.data() as Map<String, dynamic>, doc.id))
        .toList();
    // Filtrar: entregadas (ambos true)
    return tasks.where((task) => task.isCompleted && task.isSubmitted).toList();
  }

  Future<void> updateTaskStatus(String taskId, bool isCompleted, bool isSubmitted) async {
    await tasksCollection.doc(taskId).update({
      'isCompleted': isCompleted,
      'isSubmitted': isSubmitted,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> toggleTaskCompletion(Task task) async {
    if (task.id == null) throw Exception('Task ID is required for toggle');
    await tasksCollection.doc(task.id).update({
      'isCompleted': !task.isCompleted,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ==================== SUBJECTS METHODS ====================

  Future<String> addSubject(Subject subject) async {
    final subjectData = subject.toMap();
    final docRef = await subjectsCollection.add(subjectData);
    return docRef.id;
  }

  Future<void> updateSubject(Subject subject) async {
    if (subject.id == null) throw Exception('Subject ID is required for update');
    await subjectsCollection.doc(subject.id).update(subject.toMap());
  }

  Future<void> deleteSubject(String subjectId) async {
    await subjectsCollection.doc(subjectId).delete();
  }

  Future<List<Subject>> getSubjects() async {
    final snapshot = await subjectsCollection
        .orderBy('name')
        .get();
    return snapshot.docs
        .map((doc) => Subject.fromMap(doc.data() as Map<String, dynamic>, doc.id))
        .toList();
  }

  Future<List<Subject>> getPublicSubjects() async {
    final snapshot = await subjectsCollection
        .where('visibility', isEqualTo: SubjectVisibility.cursoCompleto.index)
        .orderBy('name')
        .get();
    return snapshot.docs
        .map((doc) => Subject.fromMap(doc.data() as Map<String, dynamic>, doc.id))
        .toList();
  }
}
