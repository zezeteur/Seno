class Reseau {
  final String id;
  final String nom;
  final String abreviation;
  final bool statut;
  final String logo;

  Reseau({
    required this.id,
    required this.nom,
    required this.abreviation,
    required this.statut,
    required this.logo,
  });

  factory Reseau.fromJson(Map<String, dynamic> json) {
    return Reseau(
      id: json['id'] as String,
      nom: json['nom'] as String,
      abreviation: json['abreviation'] as String,
      statut: json['statut'] as bool,
      logo: json['logo'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nom': nom,
      'abreviation': abreviation,
      'statut': statut,
      'logo': logo,
    };
  }
}
