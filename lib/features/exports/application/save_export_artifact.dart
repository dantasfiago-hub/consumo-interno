import '../../../core/types/json.dart';
import '../domain/export.dart';

enum ExportSaveResult { cancelled, saved }

/// Protects a reservation before bytes leave the application. A cancelled picker
/// never records a successful save, but keeps the conservative cloud protection.
Future<ExportSaveResult> saveExportArtifact(
  Json batch, {
  required Future<Json> Function(Json) authorize,
  required Future<String?> Function(ExportArtifact) write,
  required Future<void> Function(Json) recordSaved,
}) async {
  var current = batch;
  var artifact = ExportArtifact.fromJson(
    Map<String, dynamic>.from(current['artifact']),
  );
  if (current['status'] == 'cancelled') throw StateError('Lote cancelado.');
  if (current['status'] == 'prepared') {
    current = await authorize(current);
    artifact = ExportArtifact.fromJson(
      Map<String, dynamic>.from(current['artifact']),
    );
  }
  if (!['ready', 'downloaded', 'imported'].contains(current['status'])) {
    throw StateError('Gravação não autorizada.');
  }
  final path = await write(artifact);
  if (path == null) return ExportSaveResult.cancelled;
  await recordSaved(current);
  return ExportSaveResult.saved;
}
