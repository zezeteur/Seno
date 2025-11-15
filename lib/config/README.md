# Configuration de l'application (Production)

Ce dossier contient les fichiers de configuration de l'application Seno pour la production.

## Fichier de configuration

Le fichier `app_config.dart` contient toutes les clés et configurations de l'application.

## Utilisation

### Variables d'environnement (Obligatoire)

Toutes les clés doivent être fournies via des variables d'environnement lors de la compilation :

```bash
# Pour la production Android
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=API_BASE_URL=https://api.example.com \
  --dart-define=ENVIRONMENT=production

# Pour la production iOS
flutter build ios --release \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=API_BASE_URL=https://api.example.com \
  --dart-define=ENVIRONMENT=production
```

## Variables disponibles

### Supabase
- `SUPABASE_URL` : URL de votre projet Supabase
- `SUPABASE_ANON_KEY` : Clé anonyme (publique)
- `SUPABASE_SERVICE_ROLE_KEY` : Clé de service (secrète, côté serveur uniquement)

### API
- `API_BASE_URL` : URL de base de l'API
- `API_KEY` : Clé API

### Paiement
- `PAYMENT_PUBLIC_KEY` : Clé publique de paiement
- `PAYMENT_SECRET_KEY` : Clé secrète de paiement (serveur uniquement)

### Application
- `ENVIRONMENT` : development, staging, production
- `DEBUG` : true/false

### Feature Flags
- `ENABLE_ANALYTICS` : true/false
- `ENABLE_CRASH_REPORTING` : true/false

## Sécurité

⚠️ **IMPORTANT** : Ne jamais commiter les fichiers contenant des clés secrètes dans Git !

- Le fichier `.env` est exclu du versionnement
- Utilisez toujours des variables d'environnement pour les clés sensibles
- Les clés secrètes ne doivent jamais être dans le code source

