import 'package:uuid/uuid.dart';
import 'app_logger.dart';

/// Distributed Tracing utility for observability across the mesh network.
class DistributedTracer {
  static const _uuid = Uuid();

  /// Generate a globally unique Trace ID.
  static String generateTraceId() => _uuid.v4().replaceAll('-', '');

  /// Generate a unique Span ID for a local operation.
  static String generateSpanId() => _uuid.v4().replaceAll('-', '').substring(0, 16);

  /// Log a distributed trace event.
  static void logEvent(
    String event, {
    required String traceId,
    String? spanId,
    Map<String, dynamic>? attributes,
  }) {
    final sId = spanId ?? 'no-span';
    final attrs = attributes != null ? ' | attrs: $attributes' : '';
    AppLogger.i('[TRACE] [trace:$traceId] [span:$sId] $event$attrs');
  }

  /// Log the start of an operation span.
  static void startSpan(
    String operationName, {
    required String traceId,
    required String spanId,
    Map<String, dynamic>? attributes,
  }) {
    logEvent('Span Started: $operationName', traceId: traceId, spanId: spanId, attributes: attributes);
  }

  /// Log the end of an operation span.
  static void endSpan(
    String operationName, {
    required String traceId,
    required String spanId,
    Map<String, dynamic>? attributes,
  }) {
    logEvent('Span Ended: $operationName', traceId: traceId, spanId: spanId, attributes: attributes);
  }
}
