import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/food_db_entry.dart';

/// Lookup result from OpenFoodFacts. Returned by [OpenFoodFactsService.lookup].
class BarcodeLookupResult {
  /// The DB-shaped entry, ready to scale via [FoodDbEntry.toFoodEntry].
  /// Macros are per 100g; calorie value is rounded to integer.
  final FoodDbEntry entry;

  /// Best display name combining brand + product where both exist
  /// ("Bear Brand · Sterilized Milk"). Used for the confirm sheet only —
  /// [entry.name] is what's persisted.
  final String displayName;

  /// Image URL from OpenFoodFacts when available; null otherwise.
  final String? imageUrl;

  const BarcodeLookupResult({
    required this.entry,
    required this.displayName,
    this.imageUrl,
  });
}

/// Looks up packaged products by barcode against the OpenFoodFacts public API.
/// Free, no auth, no rate limit (within reason). Coverage is global with
/// hundreds of thousands of PH-tagged products; quality varies by product.
///
/// V1 contract: one shot, no caching here. The presenter caches confirmed hits
/// into the personal-food dictionary so repeat scans are instant + offline.
class OpenFoodFactsService {
  /// API v2 product endpoint. Returns 200 + `{status: 0}` for unknown
  /// barcodes — we treat that as "not found", not an error.
  static const _baseUrl = 'https://world.openfoodfacts.org/api/v2/product';

  /// User-Agent is required by OpenFoodFacts ToS — they identify clients in
  /// their logs to debug abuse + reach out about bad traffic.
  static const _userAgent = 'IntermittentFastingApp/1.0 (flutter)';

  /// Network timeout — OFF responses are typically <500ms but the public API
  /// can spike under load. We bound at 8s and fail loud rather than freeze
  /// the scan UI.
  static const _timeout = Duration(seconds: 8);

  final http.Client _client;

  OpenFoodFactsService({http.Client? client})
      : _client = client ?? http.Client();

  /// Look up [barcode] (EAN-13, UPC-A, EAN-8, etc.). Returns null when the
  /// barcode is unknown to OFF or required nutrition fields are missing.
  /// Network errors throw — callers should catch and show a friendly message.
  Future<BarcodeLookupResult?> lookup(String barcode) async {
    final cleaned = barcode.trim();
    if (cleaned.isEmpty) return null;

    final uri = Uri.parse(
      '$_baseUrl/$cleaned.json'
      '?fields=product_name,brands,nutriments,image_small_url,countries_tags',
    );

    final response = await _client
        .get(uri, headers: {'User-Agent': _userAgent}).timeout(_timeout);

    if (response.statusCode != 200) {
      debugPrint(
          'OpenFoodFactsService: HTTP ${response.statusCode} for $cleaned');
      return null;
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('OpenFoodFactsService: bad JSON for $cleaned: $e');
      return null;
    }

    return parseProduct(barcode: cleaned, json: json);
  }

  /// Pure parser — separated from `lookup` so tests don't need an HTTP mock.
  /// Returns null when fields are missing/invalid; the caller treats null as
  /// "not enough data to log" (different from "barcode unknown").
  @visibleForTesting
  static BarcodeLookupResult? parseProduct({
    required String barcode,
    required Map<String, dynamic> json,
  }) {
    // status==0 means OFF doesn't have this barcode at all.
    if (json['status'] == 0) return null;

    // Tolerant casts: `jsonDecode` produces Map<String, dynamic>, but other
    // call paths (tests, hand-built fixtures) sometimes pass Map<dynamic, _>.
    final productRaw = json['product'];
    if (productRaw is! Map) return null;
    final product = Map<String, dynamic>.from(productRaw);

    final productName = (product['product_name'] as String?)?.trim() ?? '';
    final brands = (product['brands'] as String?)?.trim() ?? '';
    if (productName.isEmpty && brands.isEmpty) return null;

    final nutrimentsRaw = product['nutriments'];
    if (nutrimentsRaw is! Map) return null;
    final nutriments = Map<String, dynamic>.from(nutrimentsRaw);

    // Energy: prefer kcal_100g; fall back to kJ_100g (× 0.239) when only kJ
    // is reported (common for European products).
    double? cal = _num(nutriments['energy-kcal_100g']);
    if (cal == null) {
      final kj = _num(nutriments['energy-kj_100g']);
      if (kj != null) cal = kj * 0.239;
    }
    if (cal == null || cal <= 0) return null;

    final protein = _num(nutriments['proteins_100g']);
    final carbs = _num(nutriments['carbohydrates_100g']);
    final fat = _num(nutriments['fat_100g']);

    // Build the canonical name as "Brand Product" (avoid duplicating brand
    // when product_name already contains it). e.g. "Bear Brand Sterilized Milk"
    // not "Bear Brand Bear Brand Sterilized Milk".
    final String name;
    final String displayName;
    if (brands.isEmpty) {
      name = productName;
      displayName = productName;
    } else if (productName.isEmpty) {
      name = brands;
      displayName = brands;
    } else {
      // First brand only when comma-separated (OFF stores "Brand1,Brand2").
      final firstBrand = brands.split(',').first.trim();
      final lower = productName.toLowerCase();
      final brandLower = firstBrand.toLowerCase();
      name =
          lower.contains(brandLower) ? productName : '$firstBrand $productName';
      displayName =
          firstBrand.isNotEmpty ? '$firstBrand · $productName' : productName;
    }

    return BarcodeLookupResult(
      entry: FoodDbEntry(
        // Stable id namespace so repeat scans + dedup work cleanly.
        id: 'off_$barcode',
        name: name,
        caloriesPer100g: double.parse(cal.toStringAsFixed(1)),
        proteinPer100g: protein,
        carbsPer100g: carbs,
        fatPer100g: fat,
        category: 'Barcode (OpenFoodFacts)',
      ),
      displayName: displayName,
      imageUrl: product['image_small_url'] as String?,
    );
  }

  static double? _num(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  void dispose() => _client.close();
}
