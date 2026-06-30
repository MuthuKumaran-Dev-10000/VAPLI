// lib/core/utils/file_folder_opener.dart
// ══════════════════════════════════════════════════════════════════════════════
// Utility to open files and folders on both Windows and Android
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';

class FileFolderOpener {
  static const _channel = MethodChannel('com.lubeindicator.vapli/open_file');

  /// Opens a file using default system viewer
  static Future<void> openFile(String filePath) async {
    if (Platform.isWindows) {
      final normalized = filePath.replaceAll('/', '\\');
      final result = await Process.run('explorer.exe', [normalized]);
      if (result.exitCode != 0) {
        // Fallback using cmd's start command
        await Process.run('cmd', ['/c', 'start', '', normalized]);
      }
    } else if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('openFile', {'path': filePath});
      } on PlatformException catch (e) {
        throw 'Failed to open file: ${e.message}';
      }
    } else {
      await OpenFilex.open(filePath);
    }
  }

  /// Opens a folder (directory) using the system file manager / app chooser
  static Future<void> openFolder(String folderPath) async {
    if (Platform.isWindows) {
      final normalized = folderPath.replaceAll('/', '\\');
      final result = await Process.run('explorer.exe', [normalized]);
      if (result.exitCode != 0) {
        // Fallback using cmd's start command
        await Process.run('cmd', ['/c', 'start', '', normalized]);
      }
    } else if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('openFolder', {'path': folderPath});
      } on PlatformException catch (e) {
        throw 'Failed to open folder: ${e.message}';
      }
    } else {
      // Fallback
      await OpenFilex.open(folderPath);
    }
  }
}
