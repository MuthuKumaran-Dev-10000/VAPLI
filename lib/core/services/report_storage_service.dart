import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';

class ReportStorageService {
  static const _channel = MethodChannel('com.lubeindicator.vapli/media_scanner');

  /// Resolves the candidate directories in priority order:
  /// 1. `/storage/emulated/0/Documents/VAPLI`
  /// 2. `/storage/emulated/0/Download/VAPLI`
  /// 3. `/storage/emulated/0/VAPLI`
  /// 4. App-private external directory (fallback)
  /// 5. App Documents directory (fallback)
  /// 6. Temporary directory (fallback)
  static Future<List<Directory>> getBaseDirectories() async {
    final List<Directory> dirs = [];

    if (Platform.isAndroid) {
      // Candidates on Android
      // 1. Documents
      dirs.add(Directory('/storage/emulated/0/Documents/VAPLI'));
      // 2. Download
      dirs.add(Directory('/storage/emulated/0/Download/VAPLI'));
      // 3. Root of Internal Storage
      dirs.add(Directory('/storage/emulated/0/VAPLI'));

      // 4. App-private external directory
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          dirs.add(Directory('${extDir.path}/VAPLI'));
        }
      } catch (_) {}
    }

    // 5. App documents directory (standard for iOS and backup fallback for Android)
    try {
      final docDir = await getApplicationDocumentsDirectory();
      dirs.add(Directory('${docDir.path}/VAPLI'));
    } catch (_) {}

    // 6. Temporary directory (last resort)
    try {
      final tempDir = await getTemporaryDirectory();
      dirs.add(Directory('${tempDir.path}/VAPLI'));
    } catch (_) {}

    return dirs;
  }

  /// Saves a file with duplicate protection, integrity check, Android media indexing, and logging.
  /// returns the created File.
  static Future<File> saveFile({
    required String fileName,
    required List<int> bytes,
    required String subPath, // e.g. 'Reports/PDF', 'Reports/Excel', 'Images/Annotated', 'Backups'
    required String exportType, // 'PDF Report', 'Excel Report', 'Structure Backup'
    required String username,
    required String clientName,
  }) async {
    // 1. Try to request storage permission (don't fail if rejected, fallbacks will handle it)
    try {
      if (Platform.isAndroid) {
        await Permission.storage.request();
      }
    } catch (_) {}

    final baseDirs = await getBaseDirectories();
    Directory? chosenBaseDir;
    File? finalFile;
    FileSystemException? lastException;

    // 2. Iterate through base directory candidates in priority order
    for (final baseDir in baseDirs) {
      try {
        // Create full structure
        final targetDir = Directory('${baseDir.path}/$subPath');
        await targetDir.create(recursive: true);

        // Ensure other VAPLI folders exist for clean technician/IT access
        await Directory('${baseDir.path}/Reports/PDF').create(recursive: true);
        await Directory('${baseDir.path}/Reports/Excel').create(recursive: true);
        await Directory('${baseDir.path}/Images/Annotated').create(recursive: true);
        await Directory('${baseDir.path}/Images/Original').create(recursive: true);
        await Directory('${baseDir.path}/Backups').create(recursive: true);
        await Directory('${baseDir.path}/Logs').create(recursive: true);

        // Resolve duplicate filename protection
        File resolvedFile = _resolveDuplicateFilename(targetDir, fileName);

        // Write bytes and flush
        await resolvedFile.writeAsBytes(bytes, flush: true);

        // File Integrity Verification
        if (!await resolvedFile.exists()) {
          throw FileSystemException('Verification failed: Saved file does not exist', resolvedFile.path);
        }
        final length = await resolvedFile.length();
        if (length == 0) {
          try {
            await resolvedFile.delete();
          } catch (_) {}
          throw FileSystemException('Verification failed: Saved file size is 0 bytes', resolvedFile.path);
        }

        // Successfully written and verified
        chosenBaseDir = baseDir;
        finalFile = resolvedFile;
        break;
      } catch (e) {
        debugPrint('[ReportStorage] Failed writing to ${baseDir.path}: $e');
        if (e is FileSystemException) {
          lastException = e;
        } else {
          lastException = FileSystemException(e.toString());
        }
      }
    }

    if (finalFile == null || chosenBaseDir == null) {
      throw lastException ?? const FileSystemException('Unable to save report. No writable storage location was found. The report was not lost. Please check device storage permissions and available disk space.');
    }

    // 3. Android Media Scanner Registration
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('scanFile', {'path': finalFile.path});
        debugPrint('[MediaScanner] Registered with OS MediaStore: ${finalFile.path}');
      } catch (e) {
        debugPrint('[MediaScanner] Scan registration skipped/failed: $e');
      }
    }

    // 4. Local Export Logging inside VAPLI/Logs/export_logs.txt
    try {
      final logDir = Directory('${chosenBaseDir.path}/Logs');
      await logDir.create(recursive: true);
      final logFile = File('${logDir.path}/export_logs.txt');
      final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      final fileSizeKB = (bytes.length / 1024).toStringAsFixed(2);
      final logLine = '[$timestamp] TYPE: $exportType | USER: $username | CLIENT: $clientName | PATH: ${finalFile.path} | SIZE: ${fileSizeKB}KB | STATUS: success\n';
      await logFile.writeAsString(logLine, mode: FileMode.append, flush: true);
    } catch (e) {
      debugPrint('[ReportStorage] Logging failed: $e');
    }

    return finalFile;
  }

  /// Appends (1), (2), etc. if the file already exists in the folder.
  static File _resolveDuplicateFilename(Directory dir, String fileName) {
    int dotIdx = fileName.lastIndexOf('.');
    String namePart = dotIdx != -1 ? fileName.substring(0, dotIdx) : fileName;
    String extPart = dotIdx != -1 ? fileName.substring(dotIdx) : '';

    String candidateName = fileName;
    File file = File('${dir.path}/$candidateName');
    int counter = 1;

    while (file.existsSync()) {
      candidateName = '$namePart ($counter)$extPart';
      file = File('${dir.path}/$candidateName');
      counter++;
    }

    return file;
  }
}
