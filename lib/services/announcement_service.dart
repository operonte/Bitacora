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

  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  String? _watchedCareerId;
  final Set<String> _seenIds = {};

  Future<void> loadFor(String careerId) async {
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
      _seenIds
        ..clear()
        ..addAll(parsed.map((a) => a.id!));
      notifyListeners();
    } catch (e) {
      Logger.warning('No se pudieron cargar los anuncios: $e', tag: 'AnnouncementService');
    }
    _watch(careerId);
  }

  void _watch(String careerId) {
    if (_watchedCareerId == careerId && _sub != null) return;
    _sub?.cancel();
    _watchedCareerId = careerId;
    _sub = _client
        .from('announcements')
        .stream(primaryKey: ['id'])
        .eq('career_id', careerId)
        .listen(
          _onStreamRows,
          onError: (e) => Logger.warning('Stream de anuncios: $e', tag: 'AnnouncementService'),
        );
  }

  void _onStreamRows(List<Map<String, dynamic>> rows) {
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
        );
      }
    }
    _seenIds
      ..clear()
      ..addAll(parsed.where((a) => a.id != null).map((a) => a.id!));

    _announcements
      ..clear()
      ..addAll(parsed);
    notifyListeners();
  }

  Future<void> create(Announcement announcement) async {
    await _client.from('announcements').insert(announcement.toInsertRow());
  }

  Future<void> delete(String id) async {
    await _client.from('announcements').delete().eq('id', id);
  }

  void stopWatching() {
    _sub?.cancel();
    _sub = null;
    _watchedCareerId = null;
  }
}
