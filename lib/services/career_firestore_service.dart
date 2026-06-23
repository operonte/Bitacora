import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_firestore.dart';
import '../models/career_model.dart';
import '../subject_model.dart';

/// Servicio de Firestore para gestión de carreras con soporte en tiempo real.
///
/// Proporciona streams para actualizaciones en tiempo real de carreras y sus materias.
class CareerFirestoreService {
  final FirebaseFirestore _firestore = AppFirestore.instance;
  final String _collection = 'careers';

  /// Convierte un documento de la colección `careers` en un [Career].
  Career _careerFromData(Map<String, dynamic> data) {
    final subjectsList = List.from(data['predefinedSubjects'] as List<dynamic>);
    final subjects = subjectsList
        .map((s) => Subject.fromMap(Map<String, dynamic>.from(s as Map)))
        .toList();
    return Career(
      id: data['id'] as String,
      name: data['name'] as String,
      accessKey: data['accessKey'] as String,
      description: data['description'] as String?,
      predefinedSubjects: subjects,
    );
  }

  /// Carga puntual (una sola vez) de las carreras creadas en el admin.
  Future<List<Career>> fetchCustomCareers() async {
    final snapshot = await _firestore.collection(_collection).get();
    return snapshot.docs
        .map((doc) => _careerFromData(doc.data()))
        .toList();
  }

  /// Stream que emite la lista completa de carreras en tiempo real
  Stream<List<Career>> getCareersStream() {
    return _firestore.collection(_collection).snapshots().map((snapshot) {
      final customCareers = snapshot.docs
          .map((doc) => _careerFromData(doc.data()))
          .toList();

      // Combinar con carreras predefinidas (sin las remotas cacheadas para
      // evitar duplicados con las que llegan en este snapshot).
      return [...Careers.predefined, ...customCareers];
    });
  }

  /// Stream que emite los detalles de una carrera específica en tiempo real
  Stream<Career?> getCareerStream(String careerId) {
    // Primero verificar si es una carrera predefinida
    final predefinedCareer = Careers.all.firstWhere(
      (career) => career.id == careerId,
      orElse: () => Careers.all.first,
    );

    if (predefinedCareer.id == careerId) {
      // Para carreras predefinidas, emitir el valor estático
      return Stream.value(predefinedCareer);
    }

    // Para carreras personalizadas, escuchar cambios en Firestore
    return _firestore.collection(_collection).doc(careerId).snapshots().map((
      doc,
    ) {
      if (!doc.exists) return null;

      final data = doc.data()!;
      final subjectsList = List.from(data['predefinedSubjects'] as List<dynamic>);
      final subjects = subjectsList
          .map((s) => Subject.fromMap(Map<String, dynamic>.from(s as Map)))
          .toList();
      return Career(
        id: data['id'] as String,
        name: data['name'] as String,
        accessKey: data['accessKey'] as String,
        description: data['description'] as String?,
        predefinedSubjects: subjects,
      );
    });
  }

  // Crear una nueva carrera en Firebase
  Future<void> createCareer(Career career) async {
    try {
      await _firestore.collection(_collection).doc(career.id).set({
        'id': career.id,
        'name': career.name,
        'accessKey': career.accessKey,
        'description': career.description ?? '',
        'predefinedSubjects': career.predefinedSubjects
            .map((s) => s.toMap())
            .toList(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Error al crear carrera: $e');
    }
  }

  // Obtener todas las carreras (predefinidas + personalizadas)
  Future<List<Career>> getAllCareers() async {
    try {
      // Obtener carreras personalizadas de Firebase
      final snapshot = await _firestore.collection(_collection).get();
      final customCareers = snapshot.docs.map((doc) {
        final data = doc.data();
        final subjectsList = List.from(data['predefinedSubjects'] as List<dynamic>);
        final subjects = subjectsList
            .map((s) => Subject.fromMap(Map<String, dynamic>.from(s as Map)))
            .toList();
        return Career(
          id: data['id'] as String,
          name: data['name'] as String,
          accessKey: data['accessKey'] as String,
          description: data['description'] as String?,
          predefinedSubjects: subjects,
        );
      }).toList();

      // Combinar con carreras predefinidas
      final allCareers = [...Careers.all, ...customCareers];
      return allCareers;
    } catch (e) {
      throw Exception('Error al obtener carreras: $e');
    }
  }

  // Obtener una carrera por ID
  Future<Career?> getCareerById(String id) async {
    try {
      // Primero buscar en carreras predefinidas
      final predefinedCareer = Careers.all.firstWhere(
        (career) => career.id == id,
        orElse: () => Careers.all.first, // fallback
      );
      if (predefinedCareer.id == id) {
        return predefinedCareer;
      }

      // Si no está en predefinidas, buscar en Firebase
      final doc = await _firestore.collection(_collection).doc(id).get();
      if (doc.exists) {
        final data = doc.data()!;
        final subjectsList = List.from(data['predefinedSubjects'] as List<dynamic>);
        final subjects = subjectsList
            .map((s) => Subject.fromMap(Map<String, dynamic>.from(s as Map)))
            .toList();
        return Career(
          id: data['id'] as String,
          name: data['name'] as String,
          accessKey: data['accessKey'] as String,
          description: data['description'] as String?,
          predefinedSubjects: subjects,
        );
      }
      return null;
    } catch (e) {
      throw Exception('Error al obtener carrera: $e');
    }
  }

  // Actualizar una carrera existente
  Future<void> updateCareer(Career career) async {
    try {
      // Permitir actualizar cualquier carrera (incluyendo predefinidas)
      await _firestore.collection(_collection).doc(career.id).set({
        'id': career.id,
        'name': career.name,
        'accessKey': career.accessKey,
        'description': career.description ?? '',
        'predefinedSubjects': career.predefinedSubjects
            .map((s) => s.toMap())
            .toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Error al actualizar carrera: $e');
    }
  }

  // Eliminar una carrera
  Future<void> deleteCareer(String careerId) async {
    try {
      // Permitir eliminar cualquier carrera (incluyendo predefinidas)
      await _firestore.collection(_collection).doc(careerId).delete();
    } catch (e) {
      throw Exception('Error al eliminar carrera: $e');
    }
  }

  // Agregar una materia a una carrera
  Future<void> addSubjectToCareer(String careerId, Subject subject) async {
    try {
      // Permitir modificar cualquier carrera (incluyendo predefinidas)
      final doc = await _firestore.collection(_collection).doc(careerId).get();
      List<Subject> currentSubjects = [];

      if (doc.exists) {
        final data = doc.data()!;
        final subjectsList = List.from(data['predefinedSubjects'] as List<dynamic>);
        currentSubjects = subjectsList
            .map((s) => Subject.fromMap(Map<String, dynamic>.from(s as Map)))
            .toList();
      } else {
        // Si no existe en Firebase, usar las materias del modelo predefinido si aplica
        final predefinedCareer = Careers.all.firstWhere(
          (c) => c.id == careerId,
          orElse: () => Careers.all.first,
        );
        if (predefinedCareer.id == careerId) {
          currentSubjects = List.from(predefinedCareer.predefinedSubjects);
        }
      }

      if (!currentSubjects.any((s) => s.id == subject.id)) {
        currentSubjects.add(subject);
        await _firestore.collection(_collection).doc(careerId).set({
          'id': careerId,
          'name': Careers.all
              .firstWhere(
                (c) => c.id == careerId,
                orElse: () => Careers.all.first,
              )
              .name,
          'accessKey': Careers.all
              .firstWhere(
                (c) => c.id == careerId,
                orElse: () => Careers.all.first,
              )
              .accessKey,
          'description': '',
          'predefinedSubjects': currentSubjects.map((s) => s.toMap()).toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      throw Exception('Error al agregar materia: $e');
    }
  }

  // Eliminar una materia de una carrera
  Future<void> removeSubjectFromCareer(
    String careerId,
    String subjectId,
  ) async {
    try {
      // Permitir modificar cualquier carrera (incluyendo predefinidas)
      final doc = await _firestore.collection(_collection).doc(careerId).get();
      List<Subject> currentSubjects = [];

      if (doc.exists) {
        final data = doc.data()!;
        final subjectsList = List.from(data['predefinedSubjects'] as List<dynamic>);
        currentSubjects = subjectsList
            .map((s) => Subject.fromMap(Map<String, dynamic>.from(s as Map)))
            .toList();
      } else {
        // Si no existe en Firebase, usar las materias del modelo predefinido si aplica
        final predefinedCareer = Careers.all.firstWhere(
          (c) => c.id == careerId,
          orElse: () => Careers.all.first,
        );
        if (predefinedCareer.id == careerId) {
          currentSubjects = List.from(predefinedCareer.predefinedSubjects);
        }
      }

      currentSubjects.removeWhere((s) => s.id == subjectId);
      await _firestore.collection(_collection).doc(careerId).set({
        'id': careerId,
        'name': Careers.all
            .firstWhere(
              (c) => c.id == careerId,
              orElse: () => Careers.all.first,
            )
            .name,
        'accessKey': Careers.all
            .firstWhere(
              (c) => c.id == careerId,
              orElse: () => Careers.all.first,
            )
            .accessKey,
        'description': '',
        'predefinedSubjects': currentSubjects.map((s) => s.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Error al eliminar materia: $e');
    }
  }
}
