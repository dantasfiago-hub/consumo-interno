import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../../../core/access/sectors.dart';
import '../../../core/types/json.dart';

class Product {
  final String id, code, description, unit;
  final String? photo, photoHash;
  final bool active;
  final int version;
  final List<String> sectorIds;
  const Product({
    required this.id,
    required this.code,
    required this.description,
    required this.unit,
    this.photo,
    this.photoHash,
    this.active = true,
    this.version = 1,
    this.sectorIds = const [],
  });
  factory Product.fromJson(Json j) => Product(
    id: j['id'],
    code: j['code'],
    description: j['description'],
    unit: j['unit'],
    photo: j['photo'],
    photoHash: j['photo_hash'],
    active: j['active'] ?? true,
    version: j['version'] ?? 1,
    sectorIds: List<String>.from(j['sectors'] ?? []),
  );
  Json toJson() => {
    'id': id,
    'code': code,
    'description': description,
    'unit': unit,
    'photo': photo,
    if (photoHash != null) 'photo_hash': photoHash,
    'active': active,
    'version': version,
    'sectors': sectorIds,
  };
}

void validateProduct(Product p) {
  if (p.sectorIds.toSet().length != p.sectorIds.length ||
      !p.sectorIds.every(sectors.containsKey)) {
    throw const FormatException('Setores do produto inválidos.');
  }
  if (p.id.isEmpty ||
      p.version < 1 ||
      p.code.trim().isEmpty ||
      p.code.length > 40 ||
      p.description.trim().isEmpty ||
      p.description.length > 150 ||
      !['UN', 'KG'].contains(p.unit)) {
    throw const FormatException(
      'Produto inválido: confira código, descrição e unidade.',
    );
  }
  if (p.photoHash != null &&
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(p.photoHash!)) {
    throw const FormatException('Hash da foto inválido.');
  }
  if ((p.photo?.length ?? 0) > 180000) {
    throw const FormatException('Foto muito grande.');
  }
  if (p.photo != null) {
    final bytes = base64Decode(p.photo!);
    if (bytes.isEmpty) throw const FormatException('Foto inválida.');
    if (p.photoHash != null &&
        sha256.convert(bytes).toString() != p.photoHash) {
      throw const FormatException('Hash incompatível com a foto.');
    }
  }
}
