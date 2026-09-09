import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/announcement_model.dart';
import '../notification_service.dart';
import '../utils/logger.dart';
import 'supabase_service.dart';

/// Anuncios de una carrera, con actualización en vivo mientras la pantalla
/// está abierta.
///
/// A propósito sin caché en Hive: es una herramienta de uso puntual, no algo
/// que haga falta ver sin conexión como tareas o reuniones. Y a propósito
/// sin push real — no hay Firebase Cloud Messaging en el proyecto, así que
/// un anuncio urgente solo suena si la app está abierta en ese momento; con
/// la app cerrada, se ve al volver a entrar, sin sonido.
class AnnouncementService extends ChangeNotifier {
  static final AnnouncementService _instance = AnnouncementService._internal();
  factory AnnouncementService() => _instance;
  AnnouncementService._internal();

  SupabaseClient get _client => SupabaseService.client;

  final List<Announcement> _announcements = [];
  List<Announcement> get announcements => List.unmodifiable(_announcements);

  /// Una suscripción por carrera. Antes había una sola, atada a la pantalla
  /// de Anuncios: el aviso de un anuncio urgente solo sonaba si esa pantalla
  /// puntual estaba abierta en ese momento exacto, algo que en la práctica
  /// casi nunca pasa. Ahora [watchAllCareers] deja una por cada carrera del
  /// usuario, viva mientras dure la sesión, y la pantalla solo se apoya en
  /// la misma suscripción para pintar la lista.
  final Map<String, StreamSubscription<List<Map<String, dynamic>>>> _subs = {};

  /// Qué anuncios ya generaron (o no, por no ser urgentes) su chequeo de
  /// aviso. Es único para el servicio entero, no por carrera ni por quién
  /// preguntó: así, si la pantalla de Anuncios y [watchAllCareers] reciben
  /// el mismo anuncio nuevo casi al mismo tiempo, no se duplica el aviso.
  final Set<String> _seenIds = {};

  /// Carrera que se está mostrando en pantalla ahora mismo, si hay alguna.
  /// Solo esta actualiza [announcements]; las demás suscripciones en [_subs]
  /// existen únicamente para poder avisar de un anuncio urgente.
  String? _displayedCareerId;

  Future<void> loadFor(String careerId) async {
    _displayedCareerId = careerId;
    try {
      final rows = await _client
          .from('announcements')
          .select()
          .eq('career_id', careerId)
          .order('created_at', ascending: false);
      final parsed = (rows as List)
          .map((r) => Announcement.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
      _announcements
        ..clear()
        ..addAll(parsed);
      _seenIds.addAll(parsed.map((a) => a.id!));
      notifyListeners();
    } catch (e) {
      Logger.warning(
        'No se pudieron cargar los anuncios: $e',
        tag: 'AnnouncementService',
      );
    }
    _watch(careerId);
  }

  /// Dedica una suscripción de Realtime a cada carrera del usuario, para que
  /// un anuncio urgente avise sin importar qué pantalla tenga abierta. Se
  /// llama al iniciar sesión y cada vez que cambia la lista de carreras.
  void watchAllCareers(List<String> careerIds) {
    for (final id in _subs.keys.toList()) {
      if (!careerIds.contains(id) && id != _displayedCareerId) {
        _subs.remove(id)?.cancel();
      }
    }
    for (final id in careerIds) {
      _watch(id);
    }
  }

  void _watch(String careerId) {
    if (_subs.containsKey(careerId)) return;
    _subs[careerId] = _client
        .from('announcements')
        .stream(primaryKey: ['id'])
        .eq('career_id', careerId)
        .listen(
          (rows) => _onStreamRows(careerId, rows),
          onError: (e) => Logger.warning(
            'Stream de anuncios: $e',
            tag: 'AnnouncementService',
          ),
        );
  }

  void _onStreamRows(String careerId, List<Map<String, dynamic>> rows) {
    final parsed = rows.map(Announcement.fromMap).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // El stream manda la tabla completa en cada cambio, no solo la fila que
    // cambió: hay que comparar contra lo ya visto para saber qué es nuevo de
    // verdad y no volver a avisar de todo cada vez.
    for (final a in parsed) {
      if (a.id != null && !_seenIds.contains(a.id) && a.urgent) {
        NotificationService().notifyAnnouncement(
          title: a.title,
          author: a.createdByName,
          subject: a.subject,
          careerId: careerId,
        );
      }
    }
    _seenIds.addAll(parsed.where((a) => a.id != null).map((a) => a.id!));

    if (careerId == _displayedCareerId) {
      _announcements
        ..clear()
        ..addAll(parsed);
      notifyListeners();
    }
  }

  Future<void> create(Announcement announcement) async {
    await _client.from('announcements').insert(announcement.toInsertRow());
  }

  Future<void> delete(String id) async {
    await _client.from('announcements').delete().eq('id', id);
  }

  /// Deja de pintar la lista de esta pantalla — la suscripción en sí sigue
  /// viva (la administra [watchAllCareers]) para que el aviso urgente siga
  /// llegando aunque la pantalla se cierre.
  void stopWatching() {
    _displayedCareerId = null;
  }
}
