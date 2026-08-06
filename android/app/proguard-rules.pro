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

# 5. GSON + flutter_local_notifications
# Sin esto, R8 renombra las clases que el plugin serializa con GSON para
# persistir las notificaciones programadas. Al dispararse la alarma, la
# deserialización falla en silencio y el recordatorio NUNCA se muestra
# (las notificaciones inmediatas sí funcionan, porque no pasan por GSON).
# Requerido en el plugin v18 y anteriores; desde v19 vienen incluidas.
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keep class com.dexterous.** { *; }
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Conservar los campos de clases serializadas con GSON (TypeToken genérico).
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken
