class Compte {
  final String id;
  final String proprietaire;
  final String numero;
  final String idReseau;
  final DateTime createdAt;
  final DateTime updatedAt;

  Compte({
    required this.id,
    required this.proprietaire,
    required this.numero,
    required this.idReseau,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Compte.fromJson(Map<String, dynamic> json) {
    return Compte(
      id: json['id'] as String,
      proprietaire: json['proprietaire'] as String,
      numero: json['numero'] as String,
      idReseau: json['id_reseau'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'proprietaire': proprietaire,
      'numero': numero,
      'id_reseau': idReseau,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
