import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// Punto único de acceso a Firestore para toda la app.
///
/// Bitácora usa **exclusivamente** la base de datos con nombre `bitacora`;
/// nunca la base `(default)`. Cualquier servicio que necesite Firestore debe
/// usar [AppFirestore.instance] en vez de llamar a `FirebaseFirestore.instance`
/// o `instanceFor(...)` directamente, para que sea imposible apuntar por error
/// a la base equivocada (un bug silencioso: lee/escribe en una base vacía sin
/// lanzar excepción).
class AppFirestore {
  AppFirestore._();

  /// Nombre de la base de datos Firestore del proyecto. Única fuente de verdad.
  static const String databaseId = 'bitacora';

  /// Instancia de Firestore apuntando siempre a la base `bitacora`.
  ///
  /// Obtenida de forma diferida en cada acceso porque `Firebase.app()` puede
  /// no estar listo en el momento de construir algunos servicios singleton.
  static FirebaseFirestore get instance =>
      FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: databaseId);
}
