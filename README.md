# Bubble Shooter

Jeu Godot **4.7** **2v2 en réseau local** : 4 ordinateurs, chacun contrôle un cube,
caméra à la 3e personne. Un des joueurs héberge la partie (« listen server »).

## Parcours des écrans

| Écran | Scène | Mène à |
|-------|-------|--------|
| Chargement (fictif, 3 s) | `loading_screen.tscn` | Accueil |
| Accueil | `title_screen.tscn` | **Démarrer** → Hôte/IP |
| Hôte/IP | `connect_screen.tscn` | Héberger → Sélection d'équipe · Rejoindre → connexion réussie ? oui : Sélection d'équipe, non : reste ici avec un message |
| Sélection d'équipe | `team_select.tscn` | **Lancer la partie** (hôte) → GAME |
| GAME | `game/game.tscn` | Pause (hôte) · fin du combat → Écran de fin |
| Pause (dans GAME) | `pause_menu.tscn` | Reprendre → GAME · Quitter → Sélection d'équipe (tout le monde) |
| Écran de fin | `end_screen.tscn` | **Rejouer** → Sélection d'équipe · **Quitter** → ferme le jeu |

Chaque écran est une scène indépendante de `scenes/ui/` (script du même nom dans `scripts/ui/`).
Les chemins sont regroupés dans `scripts/ui/screens.gd` (`Screens.TITLE`, `Screens.GAME`…).

## Lancer une partie

1. **Même réseau** : tous les ordinateurs sur le même Wi-Fi. Le plus simple est le partage de
   connexion du téléphone de l'hôte (voir [Réseau](#réseau)).
2. L'hôte lance le jeu, appuie sur **Démarrer** puis **Héberger la partie** : son adresse IP s'affiche.
   **Un seul hôte par réseau** : dès qu'une partie est détectée, « Héberger » est désactivé chez les autres.
3. Les autres lancent le jeu, appuient sur **Démarrer** : l'IP de l'hôte est pré-remplie si la partie
   est détectée (sinon la saisir), puis **Rejoindre**.
4. Chacun choisit son joueur avec le joystick gauche ou ← → (un joueur déjà pris est grisé),
   puis valide avec **A** : le curseur passe sur « Lancer la partie ».
   Équipe 1 : rouge (J1) + jaune (J2) · Équipe 2 : bleu (J3) + vert (J4).
5. L'hôte appuie sur **Start** (bouton +), ou A / Entrée sur « Lancer la partie » : la partie se lance pour tous,
   même s'il manque des joueurs (les cubes non choisis restent immobiles).

6. En jeu, l'hôte peut mettre en pause (**P** ou **+**) : la partie est figée pour tous.
   « Quitter » ramène tout le monde à la sélection d'équipe.
7. Fin du combat : écran des scores (fictifs pour l'instant), **Rejouer** (retour à la sélection
   d'équipe) ou **Quitter** (ferme le jeu). En attendant la vraie règle de victoire, la fin se
   déclenche avec le bouton « [Test] Terminer le combat » du menu pause (versions de développement
   uniquement) ou après `match_duration` secondes (propriété de `Game`, 0 = pas de limite).

Dans l'éditeur : **F5** lance le jeu depuis l'écran de chargement, **F6** sur `scenes/game/game.tscn` lance le jeu seul
(hors ligne, on contrôle le joueur 1).

## Contrôles

| Action | Clavier + trackpad | Manette (Switch Pro) |
|--------|-------------------------------|----------------------|
| Se déplacer | Z/Q/S/D (W/A/S/D en QWERTY) ou flèches | Joystick gauche |
| Tourner la caméra | Souris / trackpad | Joystick droit |
| Sauter | Espace | B (bouton du bas) |
| **Menus** : naviguer / choisir son joueur | Flèches (Q/D) | Joystick gauche / croix |
| **Menus** : valider | Entrée | A (bouton de droite) |
| **Sélection** : changer de joueur après validation | Retour arrière | B (bouton du bas) |
| **Sélection** : lancer la partie (hôte) | Entrée sur « Lancer la partie » | Start (+) |
| **En jeu** : pause (hôte uniquement) | P | Start (+) |
| **Pause** : reprendre (hôte) | P / Échap / Retour arrière | + / B |
| Retour à l'écran précédent (menus) | Échap | — |
| Quitter le jeu (accueil, en jeu, écran de fin) | Échap | — |

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
│   ├── themes/ui_theme.tres # Thème commun à tous les écrans (taille de police…)
│   ├── audio/{music,sfx}/
│   ├── fonts/
│   ├── icons/               # icon.svg (icône du projet)
│   ├── materials/
│   ├── models/
│   └── textures/
├── scenes/                  # Scènes (.tscn), un sous-dossier par domaine
│   ├── ui/                  # Un fichier par écran, modifiable indépendamment
│   │   ├── loading_screen.tscn  # Écran de chargement (scène de départ)
│   │   ├── title_screen.tscn    # Écran d'accueil : « Bubble Shooter » + Démarrer
│   │   ├── connect_screen.tscn  # Écran hôte/IP : Héberger / Rejoindre
│   │   ├── team_select.tscn     # Sélection d'équipe (choix des joueurs)
│   │   ├── pause_menu.tscn      # Menu pause (instancié dans game.tscn)
│   │   └── end_screen.tscn      # Écran de fin : scores, équipe gagnante, Rejouer / Quitter
│   ├── game/game.tscn       # Partie : Arena + Players/Player1..4 + PauseMenu
│   ├── levels/arena.tscn    # Sol, lumière, environnement
│   └── player/
│       ├── player.tscn          # Scène de base : cube + caméra + synchro réseau (Sync)
│       ├── player_1.tscn … player_4.tscn  # Une scène héritée par joueur (id → couleur, équipe)
│       └── player_camera.tscn   # Caméra 3e personne (SpringArm3D)
└── scripts/                 # Scripts GDScript, même découpage que scenes/
    ├── autoload/input_manager.gd    # Actions d'entrée (clavier + toutes les manettes)
    ├── autoload/network_manager.gd  # Héberger/rejoindre, joueurs, lancement, pause, fin de combat
    ├── autoload/lan_discovery.gd    # Annonce/détection de l'hôte sur le réseau local (UDP 7778)
    ├── ui/screens.gd                # Chemins de tous les écrans (Screens.*)
    ├── ui/<écran>.gd                # Un script par scène de scenes/ui/
    ├── game/game.gd                 # Autorité réseau + caméra de chaque cube, fin du combat
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
- Pause, retour à la sélection d'équipe et fin du combat sont décidés par l'hôte et appliqués
  sur tous les ordinateurs (RPC de `NetworkManager`).
- **Un seul hôte** : l'hôte diffuse une annonce UDP (port **7778**) toutes les 0,5 s ; l'écran
  hôte/IP l'écoute, désactive « Héberger » et pré-remplit l'IP. Si le réseau bloque la diffusion,
  rien n'est détecté et on saisit l'IP à la main.
- Si l'hôte quitte, les autres reviennent à l'écran hôte/IP avec un message.
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
- Les actions d'entrée (`move_*`, `look_*`, `jump`, `pause`, `menu_*`…) sont créées par l'autoload
  `InputManager` ; elles acceptent le clavier et toutes les manettes.
- Changer d'écran : `get_tree().change_scene_to_file(Screens.XXX)` (sauf les transitions
  réseau, faites par `NetworkManager` pour que tous les ordinateurs suivent).
- Calques physiques : 1 = `world`, 2 = `players`.

### Ajouter un niveau

1. Créer une scène dans `scenes/levels/` (décor uniquement, sans joueurs).
2. Remplacer l'instance `Arena` dans `scenes/game/game.tscn` par ce nouveau niveau,
   et ajuster la position des joueurs si besoin.
