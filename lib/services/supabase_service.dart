import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/logger.dart';

/// Cliente Supabase singleton para toda la app.
/// Equivale al antiguo AppFirestore.instance
class SupabaseService {
  static const String _url = 'https://pigrmmxmcmtdppkhnsbw.supabase.co';
  static const String _anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBpZ3JtbXhtY210ZHBwa2huc2J3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUxNTM2NzMsImV4cCI6MjEwMDcyOTY3M30.Qv2VGZh-rChFcjTSHLzROhlHSs-q_5MZfKGZ_wFkDW0';

  /// Inicializa Supabase. Llamar una sola vez en main().
  static Future<void> initialize() async {
    Logger.info('Inicializando Supabase...', tag: 'SupabaseService');
    await Supabase.initialize(
      url: _url,
      // ignore: deprecated_member_use
      anonKey: _anonKey,
      debug: false,
    );
    Logger.info('Supabase inicializado correctamente', tag: 'SupabaseService');
  }

  /// Acceso directo al cliente Supabase
  static SupabaseClient get client => Supabase.instance.client;
}
