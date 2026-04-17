import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'task_model.dart';

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
        .where('isCompleted', isEqualTo: false)
        .where('dueDate', isGreaterThan: DateTime.now().millisecondsSinceEpoch)
        .orderBy('dueDate')
        .get();
    return snapshot.docs
        .map((doc) => Task.fromMap(doc.data() as Map<String, dynamic>, doc.id))
        .toList();
  }

  Future<List<Task>> getOverdueTasks() async {
    final snapshot = await tasksCollection
        .where('isCompleted', isEqualTo: false)
        .where('dueDate', isLessThan: DateTime.now().millisecondsSinceEpoch)
        .orderBy('dueDate', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => Task.fromMap(doc.data() as Map<String, dynamic>, doc.id))
        .toList();
  }

  Future<void> toggleTaskCompletion(Task task) async {
    if (task.id == null) throw Exception('Task ID is required for toggle');
    await tasksCollection.doc(task.id).update({
      'isCompleted': !task.isCompleted,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }
}
