import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:re_better_auth/src/better_fetch/plugins.dart';
import 'package:re_better_auth/src/better_fetch/types.dart';

/// A [FetchEsque] backed by [dio]: no status validation, body read as bytes.
FetchEsque dioFetch(Dio dio) => (Object url, RequestContext init) async {
  final uri = url is Uri ? url : Uri.parse(url.toString());
  final response = await dio.requestUri<List<int>>(
    uri,
    data: init.body,
    cancelToken: init.signal,
    options: Options(
      method: init.method,
      headers: init.headers,
      responseType: ResponseType.bytes,
      validateStatus: (_) => true,
      receiveDataWhenStatusError: true,
    ),
  );
  final data = response.data;
  return FetchResponse(
    status: response.statusCode ?? 0,
    statusText: response.statusMessage ?? '',
    headers: FetchHeaders(response.headers.map),
    bodyBytes: data is Uint8List ? data : Uint8List.fromList(data ?? const []),
    url: response.realUri,
  );
};
