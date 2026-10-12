# GameJamShooter

Template Godot **4.7** pour un jeu local jusqu'à **4 joueurs**, caméra à la 3e personne.
Le jeu se lance en plein écran ; seule la caméra du joueur 1 (rouge) est affichée.

## Lancer le projet

1. Ouvrir Godot 4.7+, cliquer sur **Importer** et sélectionner `project.godot`.
2. Appuyer sur **F5** (ou ▶) pour lancer la scène principale `scenes/game/game.tscn`.

## Contrôles

| Joueur | Couleur | Périphérique |
|--------|---------|--------------|
| 1 | 🟥 Rouge | Clavier + trackpad **et** manette n°1 |
| 2 | 🟨 Jaune | Manette n°2 |
| 3 | 🟦 Bleu  | Manette n°3 |
| 4 | 🟩 Vert  | Manette n°4 |

| Action | Clavier + trackpad (joueur 1) | Manette (Switch Pro) |
|--------|-------------------------------|----------------------|
| Se déplacer | Z/Q/S/D (W/A/S/D en QWERTY) ou flèches | Joystick gauche |
| Tourner la caméra | Souris / trackpad | Joystick droit |
| Sauter | Espace | B (bouton du bas) |
| Quitter le jeu | Échap | — |

La souris est capturée au lancement (curseur invisible) pour piloter la caméra.
Les déplacements sont relatifs à l'orientation de la caméra. Les manettes sont attribuées dans l'ordre de connexion (première manette → joueur 1, etc.).
Un joueur qui tombe de la plateforme réapparaît à son point de départ.

> **Note sur les boutons :** Godot utilise une disposition *positionnelle* (style Xbox). Le saut est sur le bouton du **bas** (`JOY_BUTTON_A` dans Godot) : B sur Switch Pro, A sur Xbox, Croix sur PlayStation. Modifiable via `JUMP_BUTTON` dans `scripts/autoload/input_manager.gd`.

## Architecture

```
.
├── project.godot            # Configuration (scène principale, autoloads, plein écran…)
├── addons/godot_ai_mcp/     # Plugin éditeur MCP (pilotage de l'éditeur par une IA)
├── assets/                  # Ressources brutes, importées par Godot
│   ├── audio/{music,sfx}/
│   ├── fonts/
│   ├── icons/               # icon.svg (icône du projet)
│   ├── materials/
│   ├── models/
│   └── textures/
├── scenes/                  # Scènes (.tscn), un sous-dossier par domaine
│   ├── game/game.tscn       # Scène principale : Arena + Players/Player1..4
│   ├── levels/arena.tscn    # Sol, lumière, environnement
│   ├── player/
│   │   ├── player.tscn          # Scène de base : cube + caméra 3e personne
│   │   ├── player_1.tscn … player_4.tscn  # Une scène héritée par joueur (id, caméra active)
│   │   └── player_camera.tscn   # Caméra 3e personne (SpringArm3D)
│   └── ui/
└── scripts/                 # Scripts GDScript, même découpage que scenes/
    ├── autoload/input_manager.gd  # Crée les actions d'entrée par joueur
    ├── game/game.gd               # Capture la souris, oriente les caméras, Échap = quitter
    ├── player/player.gd           # Mouvement, saut, couleur, respawn
    └── player/player_camera.gd    # Orbite de la caméra (joystick droit / souris)
```

**Caméra affichée :** c'est la propriété `current` du nœud `PlayerCamera/Pitch/SpringArm/Camera`,
activée uniquement dans `player_1.tscn`. Pour suivre un autre joueur, la cocher dans sa scène
(et la décocher dans `player_1.tscn`).

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
