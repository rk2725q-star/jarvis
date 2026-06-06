import 'package:dio/dio.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/network/dio_client.dart';
import '../../models/search_result_model.dart';

class DDGInstantAnswerSource {
  final Dio _dio = DioClient().dio;

  Future<AriaSearchResult?> fetchInstantAnswer({
    required String query,
    required String category,
  }) async {
    try {
      final response = await _dio.get(
        ApiConstants.ddgInstantAnswerBase,
        queryParameters: {
          'q':             query,
          'format':        'json',
          'no_redirect':   '1',
          'no_html':       '1',
          'skip_disambig': '1',
        },
      );

      if (response.statusCode != 200) return null;

      final data = response.data as Map<String, dynamic>;

      final hasAbstract = (data['AbstractText']?.toString().isNotEmpty ?? false);
      final hasAnswer   = (data['Answer']?.toString().isNotEmpty ?? false);
      final hasHeading  = (data['Heading']?.toString().isNotEmpty ?? false);

      if (!hasAbstract && !hasAnswer && !hasHeading) return null;

      if (hasAnswer && !hasAbstract) {
        data['AbstractText'] = data['Answer'];
        data['AbstractSource'] = 'DuckDuckGo';
      }

      return AriaSearchResult.fromInstantAnswer(
        raw: data,
        category: category,
      );
    } catch (e) {
      return null;
    }
  }
}
