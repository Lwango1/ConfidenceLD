# ConfidenceLD

Application de messagerie confidentielle : envoi de messages et de médias en **vue unique**. Les fichiers médias sont détruits du serveur après lecture, garantissant la confidentialité.

## Structure

```
ConfidenceLD/
├── backend/          Serveur Node.js (Express + Socket.IO + SQLite)
│   ├── src/
│   │   ├── server.js      Point d'entrée, routes API
│   │   ├── auth.js        Authentification JWT + hash des mots de passe
│   │   ├── data.js        Base de données SQLite
│   │   └── sockets.js     Messagerie temps réel + destruction vue unique
│   └── package.json
└── confidence_app/        Application mobile Flutter (Android + iOS)
```

## Configuration

L'app mobile se connecte à `http://10.0.2.2:3000` (adresse de l'émulateur Android vers le PC).
Pour un vrai téléphone, modifiez `baseUrl` dans `confidence_app/lib/services/api_service.dart`.

## Lancer le serveur

```bash
cd backend
npm install
npm start        # ou npm run dev (rechargement automatique)
# Serveur sur http://localhost:3000
```

## Lancer l'app mobile

```bash
cd confidence_app
flutter pub get
flutter run      # nécessite un émulateur Android ou un téléphone en mode débogage
```

## Fonctionnalités

- Inscription / connexion sécurisée (mot de passe hashé + token JWT)
- Liste des utilisateurs et des conversations
- Envoi de messages texte en temps réel (WebSocket)
- Envoi de photos
- **Mode vue unique** : l'image est floutée jusqu'au toucher, puis le fichier est supprimé du serveur après lecture
- Déconnexion

## Sécurité de la vue unique

1. Le média est stocké sur le serveur
2. Le destinataire reçoit une image masquée (overlay « Vue unique »)
3. Au toucher, l'image s'affiche et le client signale `media:viewed`
4. Le serveur supprime physiquement le fichier → impossible à ré-ouvrir