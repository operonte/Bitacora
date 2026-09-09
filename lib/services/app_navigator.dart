import 'package:flutter/foundation.dart';

/// Puente entre [NotificationService] (un singleton sin acceso a ningún
/// BuildContext) y la navegación real. Tocar una notificación deja acá lo
/// que hay que abrir; `MainScreen` y `AreaPersonalScreen` —que ya están
/// montadas siempre, sea que la app se abrió recién por la notificación o
/// ya estaba corriendo— escuchan estos valores y hacen la navegación con su
/// propio `context`.
///
/// Nadie más que esas dos pantallas debería tocar estos notifiers.
class AppNavigator {
  AppNavigator._();

  /// Pestaña de `MainScreen` a activar (0 Hoy, 1 Pendientes, 2 Vencidas,
  /// 3 Entregadas, 4 Mi área). `null` = nada pendiente.
  static final ValueNotifier<int?> pendingMainTab = ValueNotifier(null);

  /// Pestaña interna de "Mi área" a activar una vez que esa pantalla esté
  /// visible. `null` = nada pendiente.
  static final ValueNotifier<AreaTabTarget?> pendingAreaTab = ValueNotifier(
    null,
  );

  /// Id de carrera para abrir sus Anuncios. `null` = nada pendiente.
  static final ValueNotifier<String?> pendingAnnouncementCareerId =
      ValueNotifier(null);
}

/// Espeja los valores del enum privado `_AreaTab` de `area_personal_screen.
/// dart` — ese es privado a su archivo, así que este helper (que necesitan
/// tanto NotificationService como AreaPersonalScreen) define su propia
/// versión pública.
enum AreaTabTarget { files, meetings, teaching }
