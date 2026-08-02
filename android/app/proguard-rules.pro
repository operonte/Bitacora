# ============================================================
# BITÁCORA — Reglas de Ofuscación ProGuard / R8 Anti-Ingeniería Inversa
# ============================================================

# 1. Ofuscación estricta y eliminación de atributos de depuración
-repackageclasses ''
-allowaccessmodification
-dontusemixedcaseclassnames
-verbose

# 2. Conservar únicamente los puntos de entrada principales de Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }

# 3. Ofuscar paquetes de terceros y lógica interna de la app
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# 4. Suprimir advertencias de librerías nativas
-dontwarn io.flutter.embedding.**
