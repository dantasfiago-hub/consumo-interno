import '../../../core/types/json.dart';
import '../../reports/domain/report.dart';
import '../domain/export.dart';

/// Contract independent of HTTP and of the user interface.
abstract interface class ExportRepository {
  Future<Json> createBatch(
    List<ReportRow> rows,
    ExportProfile profile,
    Json filters,
  );
  Future<Json> updateBatch(
    Json batch,
    String action,
    String reference, {
    String? eventId,
  });
}
