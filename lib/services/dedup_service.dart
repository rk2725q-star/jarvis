import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../data/models/search_result_model.dart';

class DedupService {
  final Set<String> _exactHashes = {};
  DateTime _lastReset = DateTime.now();

  List<AriaSearchResult> deduplicate(
    List<AriaSearchResult> results,
  ) {
    _maybeResetBloom();

    final deduped = <AriaSearchResult>[];
    final seenSimHashes = <int>[];

    for (final result in results) {
      if (_exactHashes.contains(result.contentHash)) continue;

      final simHash = _computeSimHash(result.title);
      bool isNearDup = false;

      for (final existing in seenSimHashes) {
        final distance = _hammingDistance(simHash, existing);
        if (distance <= 3) {
          isNearDup = true;
          break;
        }
      }

      if (!isNearDup) {
        _exactHashes.add(result.contentHash);
        seenSimHashes.add(simHash);
        deduped.add(result);
      }
    }

    return deduped;
  }

  int _computeSimHash(String text) {
    final tokens = text
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 2);

    final v = List<int>.filled(64, 0);

    for (final token in tokens) {
      final hash = _hash64(token);
      for (int i = 0; i < 64; i++) {
        if ((hash >> i) & 1 == 1) {
          v[i] += 1;
        } else {
          v[i] -= 1;
        }
      }
    }

    int simHash = 0;
    for (int i = 0; i < 64; i++) {
      if (v[i] > 0) simHash |= (1 << i);
    }
    return simHash;
  }

  int _hash64(String token) {
    final bytes = utf8.encode(token);
    final digest = sha256.convert(bytes).bytes;
    int hash = 0;
    for (int i = 0; i < 8; i++) {
      hash |= (digest[i] << (i * 8));
    }
    return hash;
  }

  int _hammingDistance(int a, int b) {
    int xor = a ^ b;
    int count = 0;
    while (xor != 0) {
      count += xor & 1;
      xor >>= 1;
    }
    return count;
  }

  void _maybeResetBloom() {
    if (DateTime.now().difference(_lastReset).inHours >= 24) {
      _exactHashes.clear();
      _lastReset = DateTime.now();
    }
  }
}
