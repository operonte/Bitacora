class Subject {
  String? id;
  String name;
  String professor;
  String? description;
  bool isPublic;
  String userId;
  String userName;
  DateTime createdAt;

  Subject({
    this.id,
    required this.name,
    required this.professor,
    this.description,
    this.isPublic = false,
    required this.userId,
    required this.userName,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'professor': professor,
      'description': description,
      'isPublic': isPublic,
      'userId': userId,
      'userName': userName,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  factory Subject.fromMap(Map<String, dynamic> map, [String? id]) {
    return Subject(
      id: id ?? map['id']?.toString(),
      name: map['name'] ?? '',
      professor: map['professor'] ?? '',
      description: map['description'],
      isPublic: map['isPublic'] ?? false,
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? 'Usuario',
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] ?? DateTime.now().millisecondsSinceEpoch),
    );
  }

  Subject copyWith({
    String? id,
    String? name,
    String? professor,
    String? description,
    bool? isPublic,
    String? userId,
    String? userName,
    DateTime? createdAt,
  }) {
    return Subject(
      id: id ?? this.id,
      name: name ?? this.name,
      professor: professor ?? this.professor,
      description: description ?? this.description,
      isPublic: isPublic ?? this.isPublic,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
