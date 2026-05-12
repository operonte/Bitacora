import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'task_model.dart';
import 'subject_model.dart';
import 'services/local_cache_service.dart';

class FirebaseService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final LocalCacheService _cache;
  
  /// Constructor principal
  FirebaseService._internal()
      : _firestore = FirebaseFirestore.instanceFor(
          app: Firebase.app(),
          databaseId: 'dtbitacora',
        ),
        _auth = FirebaseAuth.instance,
        _cache = LocalCacheService();
  
  /// Constructor para testing (inyección de dependencias)
  FirebaseService.test({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    LocalCacheService? cache,
  })  : _firestore = firestore,
        _auth = auth,
        _cache = cache ?? LocalCacheService();
  
  /// Singleton instance
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;

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
    
    try {
      final docRef = await tasksCollection.add(taskData);
      final newTask = task.copyWith(id: docRef.id);
      
      // Guardar en caché local
      await _cache.cacheTask(newTask);
      
      return docRef.id;
    } catch (e) {
      // Si falla Firebase (sin internet), guardar en caché para sync posterior
      print('⚠️ Error guardando en Firebase, guardando en caché: $e');
      final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
      final newTask = task.copyWith(id: tempId);
      await _cache.cacheTask(newTask);
      await _cache.markPendingSync('task', tempId, 'create');
      return tempId;
    }
  }

  Future<void> updateTask(Task task) async {
    if (task.id == null) throw Exception('Task ID is required for update');
    
    try {
      await tasksCollection.doc(task.id).update(task.toMap());
      // Actualizar caché
      await _cache.cacheTask(task);
    } catch (e) {
      print('⚠️ Error actualizando en Firebase, guardando en caché: $e');
      await _cache.cacheTask(task);
      await _cache.markPendingSync('task', task.id!, 'update');
    }
  }

  Future<void> deleteTask(String taskId) async {
    try {
      await tasksCollection.doc(taskId).delete();
      // Eliminar del caché
      await _cache.removeCachedTask(taskId);
    } catch (e) {
      print('⚠️ Error eliminando en Firebase, marcando para sync: $e');
      await _cache.removeCachedTask(taskId);
      await _cache.markPendingSync('task', taskId, 'delete');
    }
  }

  Future<List<Task>> getTasks() async {
    try {
      // Intentar obtener de Firebase primero
      final snapshot = await tasksCollection
          .orderBy('createdAt', descending: true)
          .get();
      
      final tasks = snapshot.docs
          .map((doc) => Task.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
      
      // Guardar en caché para uso offline
      await _cache.cacheTasks(tasks);
      
      return tasks;
    } catch (e) {
      print('⚠️ Error cargando desde Firebase, usando caché local: $e');
      // Si falla Firebase, retornar desde caché
      return _cache.getCachedTasks();
    }
  }
  
  /// Obtiene tareas solo del caché local (útil para mostrar datos inmediatamente)
  List<Task> getTasksFromCache() {
    return _cache.getCachedTasks();
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
    
    try {
      final docRef = await subjectsCollection.add(subjectData);
      final newSubject = subject.copyWith(id: docRef.id);
      
      // Guardar en caché local
      await _cache.cacheSubject(newSubject);
      
      return docRef.id;
    } catch (e) {
      print('⚠️ Error guardando materia en Firebase, guardando en caché: $e');
      final tempId = 'temp_subject_${DateTime.now().millisecondsSinceEpoch}';
      final newSubject = subject.copyWith(id: tempId);
      await _cache.cacheSubject(newSubject);
      await _cache.markPendingSync('subject', tempId, 'create');
      return tempId;
    }
  }

  Future<void> updateSubject(Subject subject) async {
    if (subject.id == null) throw Exception('Subject ID is required for update');
    
    try {
      await subjectsCollection.doc(subject.id).update(subject.toMap());
      await _cache.cacheSubject(subject);
    } catch (e) {
      print('⚠️ Error actualizando materia en Firebase, guardando en caché: $e');
      await _cache.cacheSubject(subject);
      await _cache.markPendingSync('subject', subject.id!, 'update');
    }
  }

  Future<void> deleteSubject(String subjectId) async {
    try {
      await subjectsCollection.doc(subjectId).delete();
      await _cache.removeCachedSubject(subjectId);
    } catch (e) {
      print('⚠️ Error eliminando materia en Firebase, marcando para sync: $e');
      await _cache.removeCachedSubject(subjectId);
      await _cache.markPendingSync('subject', subjectId, 'delete');
    }
  }

  Future<List<Subject>> getSubjects() async {
    try {
      final snapshot = await subjectsCollection
          .orderBy('name')
          .get();
      
      final subjects = snapshot.docs
          .map((doc) => Subject.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
      
      // Guardar en caché para uso offline
      await _cache.cacheSubjects(subjects);
      
      return subjects;
    } catch (e) {
      print('⚠️ Error cargando materias desde Firebase, usando caché local: $e');
      // Si falla Firebase, retornar desde caché
      return _cache.getCachedSubjects();
    }
  }
  
  /// Obtiene materias solo del caché local
  List<Subject> getSubjectsFromCache() {
    return _cache.getCachedSubjects();
  }

  Future<List<Subject>> getPublicSubjects() async {
    try {
      final snapshot = await subjectsCollection
          .where('visibility', isEqualTo: SubjectVisibility.cursoCompleto.index)
          .orderBy('name')
          .get();
      return snapshot.docs
          .map((doc) => Subject.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    } catch (e) {
      print('⚠️ Error cargando materias públicas: $e');
      // Retornar vacío si falla - no usar caché para datos públicos
      return [];
    }
  }
}
