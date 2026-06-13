import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Tipos de errores de la aplicación
enum AppErrorType {
  network,
  auth,
  firebase,
  validation,
  notFound,
  permissionDenied,
  unknown,
}

/// Excepción personalizada de la aplicación
class AppException implements Exception {
  final AppErrorType type;
  final String message;
  final String? technicalDetails;
  final Exception? originalError;

  AppException({
    required this.type,
    required this.message,
    this.technicalDetails,
    this.originalError,
  });

  @override
  String toString() => message;
}

/// Mensajes de error amigables para el usuario
class ErrorMessages {
  static const String networkError =
      'No hay conexión a internet. Verifica tu red e intenta nuevamente.';
  static const String authError =
      'Error de autenticación. Por favor inicia sesión nuevamente.';
  static const String firebaseError =
      'Error al conectar con el servidor. Intenta más tarde.';
  static const String notFoundError =
      'El elemento solicitado no fue encontrado.';
  static const String permissionDeniedError =
      'No tienes permisos para realizar esta acción.';
  static const String validationError =
      'Por favor verifica los datos ingresados.';
  static const String unknownError =
      'Ocurrió un error inesperado. Intenta nuevamente.';

  /// Obtiene mensaje amigable según tipo de error
  static String getMessage(AppErrorType type) {
    switch (type) {
      case AppErrorType.network:
        return networkError;
      case AppErrorType.auth:
        return authError;
      case AppErrorType.firebase:
        return firebaseError;
      case AppErrorType.notFound:
        return notFoundError;
      case AppErrorType.permissionDenied:
        return permissionDeniedError;
      case AppErrorType.validation:
        return validationError;
      case AppErrorType.unknown:
        return unknownError;
    }
  }

  /// Clasifica un error de Firebase
  static AppException fromFirebaseError(dynamic error) {
    if (error is FirebaseAuthException) {
      return AppException(
        type: AppErrorType.auth,
        message: _getAuthErrorMessage(error.code),
        technicalDetails: error.message,
        originalError: error,
      );
    }

    if (error is FirebaseException) {
      AppErrorType type = AppErrorType.firebase;
      String message = firebaseError;

      switch (error.code) {
        case 'permission-denied':
          type = AppErrorType.permissionDenied;
          message = permissionDeniedError;
          break;
        case 'not-found':
          type = AppErrorType.notFound;
          message = notFoundError;
          break;
        case 'unavailable':
        case 'deadline-exceeded':
          type = AppErrorType.network;
          message = networkError;
          break;
      }

      return AppException(
        type: type,
        message: message,
        technicalDetails: error.message,
        originalError: error,
      );
    }

    if (error.toString().contains('SocketException') ||
        error.toString().contains('Network') ||
        error.toString().contains('connection')) {
      return AppException(
        type: AppErrorType.network,
        message: networkError,
        technicalDetails: error.toString(),
        originalError: error is Exception ? error : null,
      );
    }

    return AppException(
      type: AppErrorType.unknown,
      message: unknownError,
      technicalDetails: error.toString(),
      originalError: error is Exception ? error : null,
    );
  }

  /// Mensajes específicos de autenticación
  static String _getAuthErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'Usuario no encontrado. Verifica tu correo electrónico.';
      case 'wrong-password':
        return 'Contraseña incorrecta. Intenta nuevamente.';
      case 'invalid-email':
        return 'El correo electrónico no es válido.';
      case 'user-disabled':
        return 'Tu cuenta ha sido deshabilitada. Contacta soporte.';
      case 'too-many-requests':
        return 'Demasiados intentos. Espera un momento antes de intentar nuevamente.';
      case 'operation-not-allowed':
        return 'Esta operación no está permitida.';
      case 'account-exists-with-different-credential':
        return 'Ya existe una cuenta con este correo usando otro método de inicio de sesión.';
      default:
        return authError;
    }
  }
}

/// Utilidades para manejo de errores asíncronos
class ErrorHandler {
  /// Ejecuta una función asíncrona con manejo de errores consistente
  static Future<T?> handleAsync<T>({
    required BuildContext context,
    required Future<T> Function() operation,
    String? loadingMessage,
    String? successMessage,
    VoidCallback? onSuccess,
    VoidCallback? onError,
  }) async {
    try {
      if (loadingMessage != null && context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 16),
                Text(loadingMessage),
              ],
            ),
          ),
        );
      }

      final result = await operation();

      if (loadingMessage != null && context.mounted) {
        Navigator.pop(context); // Cerrar loading
      }

      if (successMessage != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            backgroundColor: Colors.green,
          ),
        );
      }

      onSuccess?.call();
      return result;
    } catch (error) {
      if (loadingMessage != null && context.mounted) {
        Navigator.pop(context); // Cerrar loading
      }

      final appException = ErrorMessages.fromFirebaseError(error);
      if (context.mounted) {
        showErrorSnackBar(context, appException);
      }

      onError?.call();
      return null;
    }
  }

  /// Muestra error amigable en SnackBar
  static void showErrorSnackBar(BuildContext context, AppException exception) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(exception.message),
        backgroundColor: _getErrorColor(exception.type),
        duration: const Duration(seconds: 4),
        action: exception.technicalDetails != null
            ? SnackBarAction(
                label: 'Detalles',
                textColor: Colors.white,
                onPressed: () {
                  _showErrorDetails(context, exception);
                },
              )
            : null,
      ),
    );
  }

  /// Muestra diálogo con detalles técnicos del error
  static void _showErrorDetails(BuildContext context, AppException exception) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Detalles del error'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Tipo: ${exception.type.name}'),
              const SizedBox(height: 8),
              Text('Mensaje: ${exception.message}'),
              if (exception.technicalDetails != null) ...[
                const SizedBox(height: 8),
                const Text('Detalles técnicos:'),
                Text(
                  exception.technicalDetails!,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  /// Color según tipo de error
  static Color _getErrorColor(AppErrorType type) {
    switch (type) {
      case AppErrorType.network:
        return Colors.orange;
      case AppErrorType.auth:
        return Colors.deepOrange;
      case AppErrorType.permissionDenied:
        return Colors.red;
      case AppErrorType.notFound:
        return Colors.blueGrey;
      default:
        return Colors.red;
    }
  }

  /// Verifica si hay conexión a internet (implementación básica)
  static Future<bool> hasConnection() async {
    try {
      // Intenta resolver un dominio conocido
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
