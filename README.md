# GameJamShooter

Template Godot **4.7** pour un jeu **2v2 en réseau local** : 4 ordinateurs, chacun contrôle un cube,
caméra à la 3e personne. Un des joueurs héberge la partie (« listen server »).

## Lancer une partie

1. **Même réseau** : tous les ordinateurs sur le même Wi-Fi. Le plus simple est le partage de
   connexion du téléphone de l'hôte (voir [Réseau](#réseau)).
2. L'hôte lance le jeu et clique sur **Héberger la partie** : son adresse IP s'affiche.
3. Les autres lancent le jeu, saisissent cette IP et cliquent sur **Rejoindre**.
4. Chacun choisit son joueur avec le joystick gauche ou ← → (un joueur déjà pris est grisé),
   puis valide avec **A** : le curseur passe sur « Lancer la partie ».
   Équipe 1 : rouge (J1) + jaune (J2) · Équipe 2 : bleu (J3) + vert (J4).
5. L'hôte appuie sur **Start** (bouton +), ou A / Entrée sur « Lancer la partie » : la partie se lance pour tous,
   même s'il manque des joueurs (les cubes non choisis restent immobiles).

Dans l'éditeur : **F5** lance le lobby, **F6** sur `scenes/game/game.tscn` lance le jeu seul
(hors ligne, on contrôle le joueur 1).

## Contrôles

| Action | Clavier + trackpad | Manette (Switch Pro) |
|--------|-------------------------------|----------------------|
| Se déplacer | Z/Q/S/D (W/A/S/D en QWERTY) ou flèches | Joystick gauche |
| Tourner la caméra | Souris / trackpad | Joystick droit |
| Sauter | Espace | B (bouton du bas) |
| **Lobby** : naviguer / choisir son joueur | Flèches (Q/D) | Joystick gauche |
| **Lobby** : valider (bouton, choix du joueur) | Entrée | A (bouton de droite) |
| **Lobby** : changer de joueur après validation | Retour arrière | B (bouton du bas) |
| **Lobby** : lancer la partie (hôte) | Entrée sur « Lancer la partie » | Start (+) |
| Quitter le jeu | Échap | — |

La souris est capturée au lancement (curseur invisible) pour piloter la caméra.
Chaque ordinateur contrôle son cube au clavier/trackpad **ou** avec n'importe quelle manette branchée. Les déplacements sont relatifs à la caméra.
Un joueur qui tombe de la plateforme réapparaît à son point de départ.

> **Note sur les boutons :** Godot utilise une disposition *positionnelle* (style Xbox). Le saut est sur le bouton du **bas** (`JOY_BUTTON_A` dans Godot) : B sur Switch Pro, A sur Xbox, Croix sur PlayStation. Modifiable via `JUMP_BUTTON` dans `scripts/autoload/input_manager.gd`.

## Architecture

```
.
├── project.godot            # Configuration (scène de départ, autoloads, plein écran…)
├── addons/godot_ai_mcp/     # Plugin éditeur MCP (pilotage de l'éditeur par une IA)
├── assets/                  # Ressources brutes, importées par Godot
│   ├── audio/{music,sfx}/
│   ├── fonts/
│   ├── icons/               # icon.svg (icône du projet)
│   ├── materials/
│   ├── models/
│   └── textures/
├── scenes/                  # Scènes (.tscn), un sous-dossier par domaine
│   ├── ui/lobby.tscn        # Scène de départ : consignes, Héberger/Rejoindre, choix des joueurs
│   ├── game/game.tscn       # Partie : Arena + Players/Player1..4
│   ├── levels/arena.tscn    # Sol, lumière, environnement
│   └── player/
│       ├── player.tscn          # Scène de base : cube + caméra + synchro réseau (Sync)
│       ├── player_1.tscn … player_4.tscn  # Une scène héritée par joueur (id → couleur, équipe)
│       └── player_camera.tscn   # Caméra 3e personne (SpringArm3D)
└── scripts/                 # Scripts GDScript, même découpage que scenes/
    ├── autoload/input_manager.gd    # Actions d'entrée (clavier + toutes les manettes)
    ├── autoload/network_manager.gd  # Héberger/rejoindre, attribution des joueurs, lancement
    ├── ui/lobby.gd                  # Écrans du lobby
    ├── game/game.gd                 # Autorité réseau + caméra de chaque cube, Échap = quitter
    ├── player/player.gd             # Mouvement, saut, couleur, synchro réseau
    └── player/player_camera.gd      # Orbite de la caméra (joystick droit / souris)
```

### Réseau (comment ça marche)

- **Listen server** (ENet, port **UDP 7777**) : l'hôte est serveur et joueur.
- L'hôte décide de l'attribution des joueurs (`NetworkManager.slots`) et du lancement.
- **Chaque ordinateur fait autorité sur son propre cube** : réponse instantanée, la position
  est diffusée aux autres par le `MultiplayerSynchronizer` « Sync » (propriété `sync_position`),
  et les cubes distants sont lissés (`REMOTE_SMOOTHING`). Pas d'anti-triche : prévu pour jouer entre amis.
- Les joueurs non choisis (ou dont l'ordinateur se déconnecte) passent sous l'autorité de l'hôte.
- Si l'hôte quitte, les autres reviennent au lobby avec un message.
- Tester seul : *Débogage › Personnaliser les instances lancées…* → 2 à 4 instances, puis F5.

### Réseau (se connecter avec un partage de connexion)

1. Sur le téléphone de l'hôte : activer le **partage de connexion** (iPhone : désactiver
   « Maximiser la compatibilité » pour passer en 5 GHz).
2. Connecter **les 4 ordinateurs**, y compris celui de l'hôte, à ce Wi-Fi.
3. L'IP à saisir est celle affichée par le jeu de l'hôte (sur un hotspot iPhone, du type `172.20.10.x`).
   Elle peut changer d'une session à l'autre : toujours lire celle affichée par le jeu.
4. En cas d'échec : même Wi-Fi pour tous ? pare-feu macOS (Réglages › Réseau › Coupe-feu) autorise Godot / le jeu ?

### Conventions

- Fichiers et dossiers en `snake_case`, nœuds en `PascalCase`.
- Un script dans `scripts/<domaine>/` pour une scène dans `scenes/<domaine>/`.
- Les actions d'entrée sont générées par l'autoload `InputManager` sous la forme `p<N>_<action>`
  (ex. `p2_jump`, `p3_look_left`). Utiliser `InputManager.action(player_id, &"jump")` pour récupérer le nom.
- Calques physiques : 1 = `world`, 2 = `players`.

### Ajouter un niveau

1. Créer une scène dans `scenes/levels/` (décor uniquement, sans joueurs).
2. Remplacer l'instance `Arena` dans `scenes/game/game.tscn` par ce nouveau niveau,
   et ajuster la position des joueurs si besoin.
