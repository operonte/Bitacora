import 'dart:async';

import 'package:bitacora/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bitacora/models/career_model.dart';
import 'package:bitacora/models/subject_model.dart';
import 'package:bitacora/utils/hive_box_helper.dart';
import 'career_supabase_service.dart';
import 'encryption_service.dart';

/// Servicio para gestión de carreras académicas.
///
/// Un usuario puede pertenecer a **varias** carreras/grupos a la vez. Las
/// membresías se guardan como una lista en Hive (`careers`) y una de ellas es
/// la carrera "activa" (`active_career_id`), usada para el título y como
/// destino por defecto de las tareas nuevas. Se mantiene compatibilidad con el
/// formato antiguo de una sola carrera (`selected_career`) vía migración.
class CareerService extends ChangeNotifier {
  static final CareerService _instance = CareerService._internal();
  factory CareerService() => _instance;
  CareerService._internal();

  Box? _careerBox;
  StreamSubscription? _authSubscription;

  /// Nombres de las carreras que [syncMembershipsFromServer] acaba de quitar.
  ///
  /// Sacar una carrera sin decir nada deja al usuario en la pantalla de la
  /// clave sin entender qué pasó. La pantalla lo lee una vez y lo explica.
  List<String> _recentlyRevoked = [];

  /// Devuelve y limpia el aviso pendiente: se muestra una sola vez.
  List<String> takeRevokedCareerNames() {
    final names = _recentlyRevoked;
    _recentlyRevoked = [];
    return names;
  }

  static const _careersKey = 'careers';
  static const _activeKey = 'active_career_id';
  static const _legacyKey = 'selected_career';

  /// Inicializa el servicio
  Future<void> initialize() async {
    _careerBox = await openHiveBoxSafelyUntyped('career_settings', cipher: EncryptionService.cipher);
    _migrateLegacyIfNeeded();
    await loadRemoteCareers();
    await syncMembershipsFromServer();
    _listenToAuthChanges();
  }

  /// Reconcilia al iniciar sesión: la cuenta puede ser otra, o haber entrado a
  /// una carrera desde otro dispositivo.
  void _listenToAuthChanges() {
    _authSubscription?.cancel();
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((state) async {
      if (state.session?.user == null) return;
      await loadRemoteCareers();
      await syncMembershipsFromServer();
    });
  }

  // ── Lectura ─────────────────────────────────────────────────────────

  /// Lista de carreras a las que pertenece el usuario (resueltas contra la versión más reciente en memoria/Supabase).
  List<Career> getCareers() {
    if (_careerBox == null) {
      Logger.warning('CareerService no inicializado! Hive box es null', tag: 'CareerService');
      return [];
    }
    try {
      final raw = _careerBox?.get(_careersKey);
      if (raw is! List || raw.isEmpty) {
        return [];
      }
      final stored = raw
          .map((e) => _parseCareer(e))
          .whereType<Career>()
          .toList();

      if (stored.isEmpty) {
        return [];
      }

      // Sustituir con la versión más reciente en Supabase/memoria si existe
      return stored.map((c) {
        return Careers.findById(c.id) ?? c;
      }).toList();
    } catch (e) {
      Logger.error('Error al obtener carreras desde Hive: $e', error: e, tag: 'CareerService');
      return [];
    }
  }

  /// Carrera activa (la usada para título y tareas nuevas). Devuelve la
  /// marcada como activa, o la primera de la lista, o null si no hay carreras.
  Career? getSelectedCareer() {
    final careers = getCareers();
    if (careers.isEmpty) {
      return null;
    }
    final activeId = _careerBox?.get(_activeKey) as String?;
    if (activeId != null) {
      for (final c in careers) {
        if (c.id == activeId) {
          return Careers.findById(c.id) ?? c;
        }
      }
    }
    return Careers.findById(careers.first.id) ?? careers.first;
  }

  /// Ids de todas las carreras del usuario.
  List<String> get careerIds => getCareers().map((c) => c.id).toList();

  /// Carrera que contiene la materia [subjectName], o null si ninguna la
  /// tiene o si más de una comparte ese nombre (ahí no se puede decidir sin
  /// preguntar). Sirve para proponer una carrera por defecto al subir un
  /// archivo, no para decidirla en silencio.
  String? careerIdForSubject(String subjectName) {
    final needle = subjectName.trim().toLowerCase();
    if (needle.isEmpty) return null;
    final matches = getCareers()
        .where((c) => c.predefinedSubjects
            .any((s) => s.name.trim().toLowerCase() == needle))
        .map((c) => c.id)
        .toSet();
    return matches.length == 1 ? matches.first : null;
  }

  /// Indica si el usuario pertenece a la carrera [careerId].
  bool isMember(String? careerId) {
    if (careerId == null || careerId.isEmpty) return true;
    final ids = careerIds;
    if (ids.isEmpty) return true;
    return ids.contains(careerId);
  }

  /// True si una tarea con [careerId] debe mostrarse al usuario: las tareas
  /// sin carrera (personales antiguas) se muestran siempre; el resto si
  /// pertenece a alguna carrera o si aún no hay filtro estricto.
  bool matchesAnyCareer(String? careerId) =>
      careerId == null || careerId.isEmpty || isMember(careerId);

  // ── Escritura ───────────────────────────────────────────────────────

  /// Agrega una carrera (si no está ya) y la deja como activa.
  Future<void> addCareer(Career career) async {
    final careers = getCareers();
    final exists = careers.any((c) => c.id == career.id);
    if (!exists) {
      careers.add(career);
      await _careerBox?.put(_careersKey, careers.map((c) => c.toMap()).toList());
      Logger.info('Carrera agregada: ${career.name}');
    }
    await _careerBox?.put(_activeKey, career.id);
    notifyListeners();
  }

  /// Alias compatible: agregar/seleccionar una carrera.
  Future<void> saveSelectedCareer(Career career) => addCareer(career);

  /// Marca [careerId] como carrera activa.
  Future<void> setActiveCareer(String careerId) async {
    if (!isMember(careerId)) return;
    await _careerBox?.put(_activeKey, careerId);
    notifyListeners();
  }

  /// Quita una carrera de las membresías del usuario, local y remotamente.
  ///
  /// La baja en `user_careers` es lo que realmente revoca el acceso: mientras
  /// esa fila exista, las políticas RLS siguen dejando leer las reuniones y
  /// tareas compartidas de la carrera aunque el usuario ya no la vea en su
  /// lista local. Antes solo se borraba en local y el acceso quedaba abierto.
  Future<void> removeCareer(String careerId) async {
    await _revokeRemoteMembership(careerId);

    final careers = getCareers()..removeWhere((c) => c.id == careerId);
    await _careerBox?.put(_careersKey, careers.map((c) => c.toMap()).toList());

    final activeId = _careerBox?.get(_activeKey) as String?;
    if (activeId == careerId) {
      if (careers.isNotEmpty) {
        await _careerBox?.put(_activeKey, careers.first.id);
      } else {
        await _careerBox?.delete(_activeKey);
      }
    }
    Logger.info('Carrera removida: $careerId');
    notifyListeners();
  }

  /// Borra la membresía en Supabase. La política user_careers_delete_own ya
  /// permite que cada usuario elimine las suyas.
  Future<void> _revokeRemoteMembership(String careerId) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await Supabase.instance.client
          .from('user_careers')
          .delete()
          .eq('user_id', uid)
          .eq('career_id', careerId);
    } catch (e) {
      // Si falla (offline), la carrera igual desaparece en local, pero el
      // acceso remoto sigue vigente hasta que se reintente.
      Logger.warning(
        'No se pudo revocar la membresía remota de $careerId: $e',
        tag: 'CareerService',
      );
    }
  }

  /// Deja la lista local igual a las membresías reales de `user_careers`.
  ///
  /// Hasta ahora eran dos verdades independientes: la lista del teléfono se
  /// mantenía sola y el servidor decidía por su cuenta qué contenido
  /// compartido entregar. Cuando se desincronizaban, la app se veía perfecta
  /// —la carrera aparecía, el título la mostraba, se podían crear tareas— y
  /// simplemente no llegaba nada de lo que otros compartían, sin ninguna
  /// pista de por qué.
  ///
  /// Ahora manda el servidor, en las dos direcciones:
  ///
  /// - Una carrera que el servidor no reconoce se quita del teléfono. La app
  ///   no puede repararlo sola: inscribirse exige la clave de acceso, que es
  ///   justamente el candado que protege la carrera. Sacarla manda al usuario
  ///   a la pantalla de la clave, que es la que ya sabe usar.
  /// - Una carrera que el servidor sí reconoce y el teléfono no, se agrega.
  ///   Cubre haber entrado desde otro dispositivo.
  ///
  /// Sin conexión no hace nada: no se puede distinguir "no eres miembro" de
  /// "no pude preguntar", y ante la duda no se le quita nada al usuario.
  Future<void> syncMembershipsFromServer() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;

    Set<String> confirmed;
    try {
      final rows =
          await client.from('user_careers').select('career_id').eq('user_id', uid);
      confirmed = rows
          .map((r) => (r as Map)['career_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (e) {
      Logger.warning(
        'No se pudieron leer las membresías del servidor, se conserva la lista local: $e',
        tag: 'CareerService',
      );
      return;
    }

    final local = getCareers();
    final localIds = local.map((c) => c.id).toSet();

    final removed = localIds.difference(confirmed);
    final added = confirmed.difference(localIds);
    if (removed.isEmpty && added.isEmpty) return;

    final updated = local.where((c) => confirmed.contains(c.id)).toList();

    for (final id in added) {
      final career = Careers.findById(id);
      if (career != null) {
        updated.add(career);
      } else {
        // La carrera existe en user_careers pero no en el catálogo cargado.
        // Se omite en vez de inventar un nombre: aparecería como un id crudo.
        Logger.warning(
          'Membresía de una carrera desconocida ($id), se omite',
          tag: 'CareerService',
        );
      }
    }

    await _careerBox?.put(_careersKey, updated.map((c) => c.toMap()).toList());

    // Si la carrera activa era una de las que ya no están, se pasa a la
    // primera que quede; si no queda ninguna, el routing lleva solo a la
    // pantalla de clave de acceso.
    final activeId = _careerBox?.get(_activeKey) as String?;
    if (activeId != null && !confirmed.contains(activeId)) {
      if (updated.isNotEmpty) {
        await _careerBox?.put(_activeKey, updated.first.id);
      } else {
        await _careerBox?.delete(_activeKey);
      }
    }

    if (removed.isNotEmpty) {
      // `removed` sale de restarle el servidor a lo local, así que cada id
      // está sí o sí en `local` y el nombre se puede resolver directo.
      _recentlyRevoked =
          local.where((c) => removed.contains(c.id)).map((c) => c.name).toList();
      Logger.warning(
        'Carreras quitadas por no tener membresía en el servidor: ${removed.join(', ')}',
        tag: 'CareerService',
      );
    }
    if (added.isNotEmpty) {
      Logger.info(
        'Carreras agregadas desde el servidor: ${added.join(', ')}',
        tag: 'CareerService',
      );
    }

    notifyListeners();
  }

  /// Carga las carreras creadas/modificadas en el admin (Supabase) y las deja
  /// disponibles en [Careers.remote] para validar claves y resolver nombres.
  /// Best-effort: si falla (offline / sin sesión), no lanza.
  Future<void> loadRemoteCareers() async {
    try {
      Careers.remote = await CareerSupabaseService().fetchCustomCareers();
      Logger.info('Carreras remotas cargadas: ${Careers.remote.length}', tag: 'CareerService');
      notifyListeners();
    } catch (e) {
      Logger.warning('No se pudieron cargar carreras remotas: $e', tag: 'CareerService');
    }
  }

  /// Valida una clave de acceso contra el servidor y, si es correcta, deja al
  /// usuario inscrito en la carrera. Devuelve la carrera o null si no calza.
  ///
  /// Requiere conexión. La comparación no puede hacerse localmente: para eso
  /// habría que repartir las claves en la app, que es justamente el problema
  /// que se está cerrando. Las carreras a las que el usuario ya pertenece
  /// siguen funcionando offline; lo que necesita red es *entrar* a una nueva.
  Future<Career?> validateAccessKey(String accessKey) async {
    final local = Careers.findByAccessKey(accessKey);
    if (local != null) return local;

    try {
      final careerId = await CareerSupabaseService().joinCareer(accessKey);
      if (careerId == null) return null;
      await loadRemoteCareers();
      return Careers.findById(careerId);
    } catch (e) {
      Logger.warning('No se pudo validar la clave de acceso: $e', tag: 'CareerService');
      rethrow;
    }
  }

  /// Nombre legible de la carrera [careerId]: primero entre las carreras del
  /// usuario (disponibles offline), luego entre todas las conocidas.
  String? careerNameFor(String? careerId) {
    if (careerId == null || careerId.isEmpty) return null;
    for (final c in getCareers()) {
      if (c.id == careerId) return c.name;
    }
    return Careers.findById(careerId)?.name;
  }

  /// Fuerza la recarga de materias desde el código/Supabase actualizado para todas las
  /// carreras predefinidas a las que pertenece el usuario.
  Future<void> reloadCareerWithUpdatedSubjects() async {
    final careers = getCareers();
    if (careers.isEmpty) return;
    final updated = careers
        .map((c) => Careers.findById(c.id) ?? Careers.findByAccessKey(c.accessKey) ?? c)
        .toList();
    await _careerBox?.put(_careersKey, updated.map((c) => c.toMap()).toList());
    Logger.info('Carreras recargadas con materias actualizadas');
    notifyListeners();
  }

  /// Limpia TODAS las carreras (logout completo).
  Future<void> clearSelectedCareer() async {
    await _careerBox?.delete(_careersKey);
    await _careerBox?.delete(_activeKey);
    await _careerBox?.delete(_legacyKey);
    Logger.info('Carreras limpiadas');
    notifyListeners();
  }

  // ── Internos ────────────────────────────────────────────────────────

  /// Migra el formato antiguo de una sola carrera (`selected_career`) al nuevo
  /// formato de lista, si aún no se ha hecho.
  void _migrateLegacyIfNeeded() {
    if (_careerBox == null) return;
    final hasNew = _careerBox?.get(_careersKey) != null;
    final legacy = _careerBox?.get(_legacyKey);
    if (hasNew || legacy == null) return;
    try {
      final career = _parseCareer(legacy);
      if (career != null) {
        _careerBox?.put(_careersKey, [career.toMap()]);
        _careerBox?.put(_activeKey, career.id);
        Logger.info('Migrada carrera antigua "${career.name}" al nuevo formato', tag: 'CareerService');
      }
    } catch (e) {
      Logger.error('Error migrando carrera antigua: $e', error: e, tag: 'CareerService');
    }
  }

  /// Convierte un Map (de Hive) en un Career de forma defensiva.
  Career? _parseCareer(dynamic rawData) {
    try {
      if (rawData is! Map) return null;
      final Map<String, dynamic> data = rawData is Map<String, dynamic>
          ? rawData
          : rawData.cast<String, dynamic>();

      final rawSubjects = data['predefinedSubjects'];
      final List<Subject> subjects = [];
      if (rawSubjects is List) {
        for (final s in rawSubjects) {
          if (s is Map) {
            subjects.add(Subject.fromMap(s.cast<String, dynamic>()));
          }
        }
      }

      return Career(
        id: data['id']?.toString() ?? '',
        name: data['name']?.toString() ?? 'Carrera',
        accessKey: data['accessKey']?.toString() ?? '',
        predefinedSubjects: subjects,
      );
    } catch (e) {
      Logger.error('Error parseando carrera desde Hive: $e', error: e, tag: 'CareerService');
      return null;
    }
  }

  /// Cierra recursos
  @override
  void dispose() {
    _authSubscription?.cancel();
    _careerBox?.close();
    super.dispose();
  }
}

/// Extension para convertir Career a Map
extension CareerMap on Career {
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'accessKey': accessKey,
      'predefinedSubjects': predefinedSubjects.map((s) => s.toMap()).toList(),
    };
  }
}
