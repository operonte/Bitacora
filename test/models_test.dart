import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bitacora/task_model.dart';
import 'package:bitacora/subject_model.dart';
import 'package:bitacora/models/career_model.dart';

void main() {
  group('Task Model Tests', () {
    test('Task creation with required fields', () {
      final task = Task(
        title: 'Test Task',
        description: 'Test Description',
        subject: 'Math',
        professor: 'Dr. Smith',
        dueDate: DateTime(2024, 12, 31),
        type: 'trabajo',
        userId: 'user123',
        userName: 'John Doe',
        createdAt: DateTime.now(),
      );

      expect(task.title, 'Test Task');
      expect(task.description, 'Test Description');
      expect(task.subject, 'Math');
      expect(task.professor, 'Dr. Smith');
      expect(task.isCompleted, false);
      expect(task.isSubmitted, false);
    });

    test('Task toMap and fromMap serialization', () {
      final originalTask = Task(
        id: 'task123',
        title: 'Test Task',
        description: 'Test Description',
        subject: 'Math',
        professor: 'Dr. Smith',
        dueDate: DateTime(2024, 12, 31),
        type: 'trabajo',
        userId: 'user123',
        userName: 'John Doe',
        createdAt: DateTime(2024, 1, 1),
        tag: 'urgent',
        careerId: 'teologia',
      );

      final taskMap = originalTask.toMap();
      final restoredTask = Task.fromMap(taskMap, originalTask.id);

      expect(restoredTask.id, originalTask.id);
      expect(restoredTask.title, originalTask.title);
      expect(restoredTask.description, originalTask.description);
      expect(restoredTask.subject, originalTask.subject);
      expect(restoredTask.professor, originalTask.professor);
      expect(restoredTask.type, originalTask.type);
      expect(restoredTask.tag, originalTask.tag);
      expect(restoredTask.careerId, originalTask.careerId);
    });

    test('Task copyWith creates new instance with updated fields', () {
      final originalTask = Task(
        title: 'Original',
        description: 'Desc',
        subject: 'Math',
        professor: 'Prof',
        dueDate: DateTime.now(),
        type: 'trabajo',
        userId: 'user123',
        userName: 'User',
        createdAt: DateTime.now(),
      );

      final updatedTask = originalTask.copyWith(
        title: 'Updated',
        isCompleted: true,
      );

      expect(updatedTask.title, 'Updated');
      expect(updatedTask.description, originalTask.description);
      expect(updatedTask.isCompleted, true);
      expect(originalTask.isCompleted, false);
    });

    test('Task getUrgency returns correct urgency levels', () {
      final now = DateTime.now();

      final completedTask = Task(
        title: 'Completed',
        description: 'Desc',
        subject: 'Math',
        professor: 'Prof',
        dueDate: now.subtract(const Duration(days: 1)),
        isCompleted: true,
        isSubmitted: true,
        type: 'trabajo',
        userId: 'user123',
        userName: 'User',
        createdAt: DateTime.now(),
      );
      expect(completedTask.getUrgency(), TaskUrgency.completed);

      final overdueTask = Task(
        title: 'Overdue',
        description: 'Desc',
        subject: 'Math',
        professor: 'Prof',
        dueDate: now.subtract(const Duration(days: 1)),
        type: 'trabajo',
        userId: 'user123',
        userName: 'User',
        createdAt: DateTime.now(),
      );
      expect(overdueTask.getUrgency(), TaskUrgency.overdue);

      final urgentTask = Task(
        title: 'Urgent',
        description: 'Desc',
        subject: 'Math',
        professor: 'Prof',
        dueDate: now.add(const Duration(hours: 12)),
        type: 'trabajo',
        userId: 'user123',
        userName: 'User',
        createdAt: DateTime.now(),
      );
      expect(urgentTask.getUrgency(), TaskUrgency.urgent);

      final highTask = Task(
        title: 'High',
        description: 'Desc',
        subject: 'Math',
        professor: 'Prof',
        dueDate: now.add(const Duration(days: 2)),
        type: 'trabajo',
        userId: 'user123',
        userName: 'User',
        createdAt: DateTime.now(),
      );
      expect(highTask.getUrgency(), TaskUrgency.high);

      final mediumTask = Task(
        title: 'Medium',
        description: 'Desc',
        subject: 'Math',
        professor: 'Prof',
        dueDate: now.add(const Duration(days: 5)),
        type: 'trabajo',
        userId: 'user123',
        userName: 'User',
        createdAt: DateTime.now(),
      );
      expect(mediumTask.getUrgency(), TaskUrgency.medium);

      final lowTask = Task(
        title: 'Low',
        description: 'Desc',
        subject: 'Math',
        professor: 'Prof',
        dueDate: now.add(const Duration(days: 10)),
        type: 'trabajo',
        userId: 'user123',
        userName: 'User',
        createdAt: DateTime.now(),
      );
      expect(lowTask.getUrgency(), TaskUrgency.low);
    });

    test(
      'Task needsSubmittedMarker returns true when completed but not submitted',
      () {
        final task = Task(
          title: 'Test',
          description: 'Desc',
          subject: 'Math',
          professor: 'Prof',
          dueDate: DateTime.now(),
          isCompleted: true,
          isSubmitted: false,
          type: 'trabajo',
          userId: 'user123',
          userName: 'User',
          createdAt: DateTime.now(),
        );

        expect(task.needsSubmittedMarker(), true);

        final submittedTask = task.copyWith(isSubmitted: true);
        expect(submittedTask.needsSubmittedMarker(), false);
      },
    );
  });

  group('Subject Model Tests', () {
    test('Subject creation with required fields', () {
      final subject = Subject(
        name: 'Mathematics',
        professor: 'Dr. Smith',
        visibility: SubjectVisibility.soloYo,
        userId: 'user123',
        userName: 'John Doe',
        createdAt: DateTime.now(),
      );

      expect(subject.name, 'Mathematics');
      expect(subject.professor, 'Dr. Smith');
      expect(subject.visibility, SubjectVisibility.soloYo);
      expect(subject.allowedUsers, isEmpty);
    });

    test('Subject toMap and fromMap serialization', () {
      // Test con visibility = seleccionar (permite allowedUsers)
      final originalSubject = Subject(
        id: 'subject123',
        name: 'Physics',
        professor: 'Dr. Johnson',
        description: 'Advanced Physics',
        visibility: SubjectVisibility.seleccionar,
        allowedUsers: ['user1', 'user2'],
        userId: 'user123',
        userName: 'John Doe',
        createdAt: DateTime(2024, 1, 1),
      );

      final subjectMap = originalSubject.toMap();
      final restoredSubject = Subject.fromMap(subjectMap, originalSubject.id);

      expect(restoredSubject.id, originalSubject.id);
      expect(restoredSubject.name, originalSubject.name);
      expect(restoredSubject.professor, originalSubject.professor);
      expect(restoredSubject.description, originalSubject.description);
      expect(restoredSubject.visibility, originalSubject.visibility);
      expect(restoredSubject.allowedUsers, originalSubject.allowedUsers);
    });

    test('Subject copyWith creates new instance with updated fields', () {
      final originalSubject = Subject(
        name: 'Original',
        professor: 'Prof',
        visibility: SubjectVisibility.soloYo,
        userId: 'user123',
        userName: 'User',
        createdAt: DateTime.now(),
      );

      final updatedSubject = originalSubject.copyWith(
        name: 'Updated',
        visibility: SubjectVisibility.cursoCompleto,
      );

      expect(updatedSubject.name, 'Updated');
      expect(updatedSubject.professor, originalSubject.professor);
      expect(updatedSubject.visibility, SubjectVisibility.cursoCompleto);
      expect(originalSubject.visibility, SubjectVisibility.soloYo);
    });

    test('Subject visibilityText returns correct text', () {
      final soloSubject = Subject(
        name: 'Test',
        professor: 'Prof',
        visibility: SubjectVisibility.soloYo,
        userId: 'user123',
        userName: 'User',
        createdAt: DateTime.now(),
      );
      expect(soloSubject.visibilityText, 'Solo yo');

      final publicSubject = soloSubject.copyWith(
        visibility: SubjectVisibility.cursoCompleto,
      );
      expect(publicSubject.visibilityText, 'Curso completo');

      final selectiveSubject = soloSubject.copyWith(
        visibility: SubjectVisibility.seleccionar,
      );
      expect(selectiveSubject.visibilityText, 'Elegir usuarios');
    });

    test('Subject visibilityIcon returns correct icon', () {
      final soloSubject = Subject(
        name: 'Test',
        professor: 'Prof',
        visibility: SubjectVisibility.soloYo,
        userId: 'user123',
        userName: 'User',
        createdAt: DateTime.now(),
      );
      expect(soloSubject.visibilityIcon, Icons.lock);

      final publicSubject = soloSubject.copyWith(
        visibility: SubjectVisibility.cursoCompleto,
      );
      expect(publicSubject.visibilityIcon, Icons.public);

      final selectiveSubject = soloSubject.copyWith(
        visibility: SubjectVisibility.seleccionar,
      );
      expect(selectiveSubject.visibilityIcon, Icons.people);
    });
  });

  group('Career Model Tests', () {
    test('Career creation with required fields', () {
      final subject1 = Subject(
        id: 'subject_1',
        name: 'Subject 1',
        professor: 'Prof 1',
        userId: 'admin',
        userName: 'Admin',
        createdAt: DateTime.now(),
      );
      final subject2 = Subject(
        id: 'subject_2',
        name: 'Subject 2',
        professor: 'Prof 2',
        userId: 'admin',
        userName: 'Admin',
        createdAt: DateTime.now(),
      );

      final career = Career(
        id: 'teologia',
        name: 'Teología',
        accessKey: 'teologia2026',
        predefinedSubjects: [subject1, subject2],
      );

      expect(career.id, 'teologia');
      expect(career.name, 'Teología');
      expect(career.accessKey, 'teologia2026');
      expect(career.predefinedSubjects.length, 2);
    });

    test('Careers.findByAccessKey returns correct career', () {
      final found = Careers.findByAccessKey('teologia2026');
      expect(found, isNotNull);
      expect(found?.name, 'Teología');

      final notFound = Careers.findByAccessKey('invalid_key');
      expect(notFound, isNull);
    });

    test('Careers.careerNames returns list of career names', () {
      final names = Careers.careerNames;
      expect(names, contains('Teología'));
      expect(names.length, greaterThanOrEqualTo(1));
    });

    test('Careers.all contains predefined careers', () {
      expect(Careers.all.length, greaterThanOrEqualTo(1));
      expect(Careers.all.any((c) => c.id == 'teologia'), true);
    });

    test('Teología career has correct predefined subjects', () {
      final teologia = Careers.findByAccessKey('teologia2026');
      expect(teologia, isNotNull);
      expect(
        teologia!.predefinedSubjects.map((s) => s.name),
        contains('Hermenéutica bíblica'),
      );
      expect(
        teologia.predefinedSubjects.map((s) => s.name),
        contains('Hebreo'),
      );
      expect(teologia.predefinedSubjects.length, greaterThan(0));
    });
  });
}
