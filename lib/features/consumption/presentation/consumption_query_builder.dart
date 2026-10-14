import 'package:flutter/material.dart';

import '../../../app/app_state.dart';
import '../../../domain/models.dart';

/// Keeps full report reads out of the application's periodic state reload.
class ConsumptionQueryBuilder extends StatefulWidget {
  final AppState state;
  final bool active;
  final int? limit;
  final String? sectorId;
  final Widget Function(
    BuildContext context,
    List<Consumption> records,
    bool loading,
    Object? error,
  )
  builder;

  const ConsumptionQueryBuilder({
    super.key,
    required this.state,
    required this.builder,
    this.active = true,
    this.limit,
    this.sectorId,
  });

  @override
  State<ConsumptionQueryBuilder> createState() =>
      _ConsumptionQueryBuilderState();
}

class _ConsumptionQueryBuilderState extends State<ConsumptionQueryBuilder> {
  Object? _queryKey;
  Future<List<Consumption>>? _query;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      final state = widget.state;
      final active = widget.active && state.accessReady;
      final key = (
        state,
        state.dataRevision,
        state.role,
        state.sectorId,
        active,
        widget.limit,
        widget.sectorId,
      );
      if (_queryKey != key) {
        _queryKey = key;
        _query = active
            ? state.consumption.load(
                limit: widget.limit,
                sectorId: widget.sectorId,
              )
            : null;
      }
      return FutureBuilder<List<Consumption>>(
        future: _query,
        builder: (context, snapshot) {
          final ready =
              active && snapshot.connectionState == ConnectionState.done;
          return widget.builder(
            context,
            ready && !snapshot.hasError ? snapshot.data ?? [] : [],
            active && !ready,
            ready ? snapshot.error : null,
          );
        },
      );
    },
  );
}
