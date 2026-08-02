import 'package:flutter/material.dart';

/// Icono y color según la extensión de un archivo. Compartido entre
/// [StudyFile] y [TeachingMaterial], que muestran archivos subidos a Drive
/// con el mismo criterio visual.
IconData iconForFileExtension(String extension) {
  final ext = extension.toLowerCase();
  if (['pdf'].contains(ext)) return Icons.picture_as_pdf;
  if (['doc', 'docx', 'odt', 'pages', 'txt', 'rtf'].contains(ext)) return Icons.description;
  if (['xls', 'xlsx', 'ods', 'numbers', 'csv', 'tsv'].contains(ext)) return Icons.table_chart;
  if (['ppt', 'pptx', 'odp', 'key'].contains(ext)) return Icons.slideshow;
  if (['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'bmp', 'svg'].contains(ext)) return Icons.image;
  if (['mp3', 'm4a', 'wav', 'ogg', 'aac'].contains(ext)) return Icons.audiotrack;
  if (['mp4', 'webm', 'mov', 'mkv'].contains(ext)) return Icons.movie;
  return Icons.insert_drive_file;
}

Color colorForFileExtension(String extension) {
  final ext = extension.toLowerCase();
  if (['pdf'].contains(ext)) return Colors.red;
  if (['doc', 'docx', 'odt', 'pages', 'txt'].contains(ext)) return Colors.blue;
  if (['xls', 'xlsx', 'ods', 'numbers', 'csv'].contains(ext)) return Colors.green;
  if (['ppt', 'pptx', 'odp', 'key'].contains(ext)) return Colors.orange;
  if (['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext)) return Colors.purple;
  if (['mp3', 'm4a', 'wav', 'ogg', 'aac'].contains(ext)) return Colors.teal;
  if (['mp4', 'webm', 'mov'].contains(ext)) return Colors.deepOrange;
  return Colors.grey;
}

/// Extrae la extensión (sin el punto) del nombre de archivo, o cadena vacía
/// si no tiene.
String extensionOf(String fileName) {
  final parts = fileName.split('.');
  return parts.length > 1 ? parts.last : '';
}
