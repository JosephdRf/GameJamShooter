# Bubble Shooter

Jeu Godot **4.7** **2v2 en réseau local** : 4 ordinateurs, chacun contrôle un canard,
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
   Équipe bleue : J1 + J2 · Équipe rouge : J3 + J4 (couleurs dans `Player.TEAM_COLORS`).
5. L'hôte appuie sur **Start** (bouton +), ou A / Entrée sur « Lancer la partie » : la partie se lance pour tous,
   même s'il manque des joueurs (les canards non choisis restent immobiles).
   « **Attention…** » s'affiche 2 s (joueurs figés), puis « **C'est parti !** » : on peut bouger, le
   chrono et les zones démarrent.

6. En jeu, l'hôte peut mettre en pause (**P** ou **+**) : la partie est figée pour tous.
   « Quitter » ramène tout le monde à la sélection d'équipe.
7. Un **compte à rebours** (1:00 par défaut) est affiché en haut au centre ; il est figé pendant la
   pause. À 0:00, tout le monde passe à l'écran de fin. L'hôte fait foi : il envoie le temps restant
   aux autres toutes les 0,5 s. Durée réglable avec `match_duration` sur le nœud `Game`
   (0 = pas de limite, chrono masqué).
8. **Défense de zone** : une seule zone ronde est active à la fois (tirée au hasard, jamais la
   même deux fois de suite). Une équipe qui y reste **seule 10 s** la capture et gagne **2 points** ;
   la zone prend la couleur de l'équipe présente et une barre de progression s'affiche sous le
   score. Si l'équipe sort, la barre repart à 0 ; si les deux équipes sont dedans, elle est en
   pause. Une zone non capturée disparaît au bout de **20 s** (décompte en pause tant qu'une
   équipe la capture). Scores : bleu à gauche du chrono, rouge à droite. À chaque prise :
   « Ton équipe a pris la zone clé ! » ou « L'adversaire a pris la zone clé ! ».
9. Fin du combat : écran des scores de chaque équipe, **Rejouer** (retour à la sélection
   d'équipe) ou **Quitter** (ferme le jeu). Avant l'écran de fin, « Terminé ! » s'affiche 1,5 s,
   joueurs figés.

Dans l'éditeur : **F5** lance le jeu depuis l'écran de chargement, **F6** sur `scenes/game/game.tscn` lance le jeu seul
(hors ligne, on contrôle le joueur 1).

## Contrôles

| Action | Clavier + trackpad | Manette (Switch Pro) |
|--------|-------------------------------|----------------------|
| Se déplacer | Z/Q/S/D (W/A/S/D en QWERTY) ou flèches | Joystick gauche |
| Tourner la caméra | Souris / trackpad | Joystick droit |
| Sauter | Espace | B (bouton du bas) |
| Dash (au sol, toutes les 2 s) | K | Y (bouton de gauche ; Carré sur PlayStation) |
| Tirer une bulle | T | ZL / ZR (L2 / R2 sur PlayStation) |
| **Menus** : naviguer / choisir son joueur | Flèches (Q/D) | Joystick gauche / croix |
| **Menus** : valider | Entrée | A (bouton de droite) |
| **Sélection** : changer de joueur après validation | Retour arrière | B (bouton du bas) |
| **Sélection** : lancer la partie (hôte) | Entrée sur « Lancer la partie » | Start (+) |
| **En jeu** : pause (hôte uniquement) | P | Start (+) |
| **En jeu** : test, s'infliger 10 dégâts (version de développement) | H | — |
| **Pause** : reprendre (hôte) | P / Échap / Retour arrière | + / B |
| Retour à l'écran précédent (menus) | Échap | — |
| Quitter le jeu (accueil, en jeu, écran de fin) | Échap | — |

La souris est capturée au lancement (curseur invisible) pour piloter la caméra.
Chaque ordinateur contrôle son canard au clavier/trackpad **ou** avec n'importe quelle manette branchée. Les déplacements sont relatifs à la caméra.
Un joueur qui tombe de la plateforme meurt.

### Tir

- **Viseur** au centre de l'écran (`scenes/ui/crosshair.tscn`) : il se resserre et passe au rouge sur un
  adversaire. La caméra est placée façon Splatoon : derrière et au-dessus du canard, presque horizontale.
- Chaque appui tire une bulle vers le point visé (aussi vers le haut ou le bas), 4 tirs/s au plus. Elle sort
  du bout du canon du canard, petite, et atteint sa taille en 0,12 s.
- La bulle éclate au premier contact : obstacle (sol, mur, objet…), joueur (**40 dégâts** à un adversaire,
  rien à un coéquipier), mur de la zone d'apparition adverse, ou au bout de **25 m**. Le nœud est alors supprimé.
- **Zones d'apparition** : un mur invisible (calques 3 « spawn_blue » / 4 « spawn_red ») empêche les joueurs
  et les bulles de l'équipe adverse d'y entrer.
- Réglages : sur `scenes/game/bubble_projectile.tscn` (`speed`, `max_distance`, `damage`, `friendly_fire`,
  taille du mesh = taille de la zone de contact) et sur le joueur (`fire_cooldown`, groupe « Tir »).

### Vie

- Chaque joueur a **100 PV**. Pas de barre de vie : plus il en a perdu, plus l'écran se couvre de bulles,
  autour d'une ellipse dégagée au centre (3 écrans de dégâts : 100→67, 67→33, 33→0 PV ; les grosses
  bulles n'arrivent qu'avec le 3e). Les bulles restent en place, grossissent quand on perd des PV et
  rétrécissent jusqu'à disparaître quand on en regagne.
- Sans dégâts pendant 2 s, la vie remonte de **10 PV/s**.
- À 0 PV : l'écran passe en gris avec « You died », le canard disparaît, puis il réapparaît 2 s plus tard sur sa
  zone d'apparition avec 100 PV.
- Pour infliger des dégâts (futures armes) : `player.take_damage(montant)`, depuis n'importe quel ordinateur.
- Réglages (inspecteur du joueur, groupe « Vie ») : `max_health`, `regen_rate`, `regen_delay`, `respawn_delay`.

> **Note sur les boutons :** Godot utilise une disposition *positionnelle* (style Xbox). Le saut est sur le bouton du **bas** (`JOY_BUTTON_A` dans Godot) : B sur Switch Pro, A sur Xbox, Croix sur PlayStation. Le dash est sur le bouton de **gauche** (`JOY_BUTTON_X`) : Y sur Switch Pro, X sur Xbox, Carré sur PlayStation. Modifiables via `JUMP_BUTTON` / `DASH_BUTTON` dans `scripts/autoload/input_manager.gd`.

> **Manettes qui envoient de fausses valeurs** (vu avec une Switch Pro sous macOS : stick gauche annoncé
> poussé et ZR enfoncée alors que personne n'y touche) : les sticks d'une manette ne sont pris en compte
> qu'une fois vus au repos, et une gâchette qu'une fois vue relâchée. Sinon le canard avancerait tout seul.
> Les boutons de cette manette marchent toujours ; la débrancher / rebrancher relance la vérification.

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
│   ├── materials/           # duck_*.tres : matériaux texturés du canard (corps, pistolet, réservoir bleu/rouge)
│   ├── models/              # bain-de-coin-coin.blend : l'arène (importée via Blender) ; duck_v3.glb : le canard
│   └── textures/            # Textures du canard (diffuse / normal / roughness)
├── scenes/                  # Scènes (.tscn), un sous-dossier par domaine
│   ├── ui/                  # Un fichier par écran, modifiable indépendamment
│   │   ├── loading_screen.tscn  # Écran de chargement (scène de départ)
│   │   ├── title_screen.tscn    # Écran d'accueil : « Bubble Shooter » + Démarrer
│   │   ├── connect_screen.tscn  # Écran hôte/IP : Héberger / Rejoindre
│   │   ├── team_select.tscn     # Sélection d'équipe (choix des joueurs)
│   │   ├── match_hud.tscn       # HUD en jeu : compte à rebours (instancié dans game.tscn)
│   │   ├── pause_menu.tscn      # Menu pause (instancié dans game.tscn)
│   │   ├── end_screen.tscn      # Écran de fin : scores, équipe gagnante, Rejouer / Quitter
│   │   ├── death_screen.tscn    # « You died » + image grisée (instancié dans game.tscn)
│   │   ├── announcer.tscn       # Messages de match (Attention…, C'est parti !, zone, Terminé !)
│   │   ├── crosshair.tscn       # Viseur (rouge sur un adversaire)
│   │   ├── damage_overlay.tscn  # Regroupe les écrans de dégâts (instancié dans game.tscn)
│   │   └── damage/damage_screen_1..3.tscn  # Bulles sur les bords, de plus en plus couvrantes
│   ├── game/game.tscn       # Partie : Arena + Players/Player1..4 + SpawnZones (2) + Projectiles + ZoneDefenseMode (3 zones) + MatchHud + PauseMenu
│   ├── game/zone_defense.tscn   # Une zone à capturer (rayon, points, timeout, durée de capture)
│   ├── game/zone_spawn.tscn     # Zone d'apparition d'une équipe (équipe, rayon)
│   ├── game/bubble_projectile.tscn  # Bulle tirée (vitesse, portée, dégâts)
│   ├── levels/arena.tscn    # Salle de bain (.blend) + lumières + barrière invisible devant
│   └── player/
│       ├── player.tscn          # Scène de base : canard (assets/models/duck_v3.glb, animations idle/walk/run/dash) + caméra + synchro réseau
│       ├── player_1.tscn … player_4.tscn  # Une scène héritée par joueur (id → couleur, équipe)
│       └── player_camera.tscn   # Caméra 3e personne (SpringArm3D)
└── scripts/                 # Scripts GDScript, même découpage que scenes/
    ├── autoload/input_manager.gd    # Actions d'entrée (clavier + toutes les manettes)
    ├── autoload/network_manager.gd  # Héberger/rejoindre, joueurs, lancement, pause, fin de combat
    ├── autoload/lan_discovery.gd    # Annonce/détection de l'hôte sur le réseau local (UDP 7778)
    ├── ui/screens.gd                # Chemins de tous les écrans (Screens.*)
    ├── ui/<écran>.gd                # Un script par scène de scenes/ui/
    ├── levels/bathroom_import.gd    # Import du .blend : échelle, couleurs, collisions
    ├── game/game.gd                 # Autorité réseau, caméras, compte à rebours, fin du combat
    ├── game/zone_defense.gd         # Règles de capture d'une zone (ZoneDefense)
    ├── game/zone_defense_mode.gd    # Rotation des zones + scores par équipe (ZoneDefenseMode)
    ├── game/zone_spawn.gd           # Emplacements d'apparition d'une équipe (ZoneSpawn)
    ├── game/bubble_projectile.gd    # Vol, contact, dégâts et éclatement d'une bulle (BubbleProjectile)
    ├── player/player.gd             # Mouvement, saut, dash, tir, vie, couleur, synchro réseau
    └── player/player_camera.gd      # Orbite de la caméra (joystick droit / souris)
```

### Réseau (comment ça marche)

- **Listen server** (ENet, port **UDP 7777**) : l'hôte est serveur et joueur.
- L'hôte décide de l'attribution des joueurs (`NetworkManager.slots`) et du lancement.
- **Chaque ordinateur fait autorité sur son propre canard** : réponse instantanée, la position
  est diffusée aux autres par le `MultiplayerSynchronizer` « Sync » (propriété `sync_position`),
  et les canards distants sont lissés (`REMOTE_SMOOTHING`). Pas d'anti-triche : prévu pour jouer entre amis.
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
- Les actions d'entrée (`move_*`, `look_*`, `jump`, `dash`, `shoot`, `pause`, `menu_*`…) sont créées par l'autoload
  `InputManager` ; elles acceptent le clavier et toutes les manettes.
- Changer d'écran : `get_tree().change_scene_to_file(Screens.XXX)` (sauf les transitions
  réseau, faites par `NetworkManager` pour que tous les ordinateurs suivent).
- Calques physiques : 1 = `world`, 2 = `players`.

### L'arène salle de bain

- Source : `assets/models/bain-de-coin-coin.blend`. Godot l'importe avec **Blender**
  (Éditeur › Paramètres › Système de fichiers › Import › chemin de Blender) : chaque coéquipier qui
  ouvre le projet doit avoir Blender installé.
- Options d'import (onglet Import) : échelle **0,16** (le canard « hero » de Blender ≈ 1 m, la taille
  d'un joueur), caméras et lumières de Blender ignorées.
- `scripts/levels/bathroom_import.gd` s'exécute à chaque import : retire le canard héros, donne leur
  couleur aux matériaux procéduraux (exportés en blanc), et ajoute des **collisions grossières**
  (une boîte par objet ; mousse, eau, gouttes, feuilles et petits détails n'en ont pas).
  Après modification : sélectionner le `.blend` › onglet Import › **Réimporter**.
- Points d'apparition : zones `SpawnZones/ZoneSpawnBlue` (z = -16) et `ZoneSpawnRed` (z = 17, côté
  baignoire) dans `game.tscn`. Au lancement, `game.gd` place chaque joueur sur la zone de son équipe
  (côte à côte, à mi-rayon) ; un joueur qui tombe réapparaît à son emplacement. Pour les déplacer :
  bouger les zones dans la vue 3D (la position des nœuds `Player1..4` est ignorée).
- Rendu 3D à 75 % + FSR (`rendering/scaling_3d`) : ~105-135 images/s sur un MacBook M3.

### Régler les zones

Dans `scenes/game/game.tscn`, les zones sont les enfants de `ZoneDefenseMode` (`ZoneLeft`,
`ZoneCenter`, `ZoneRight`) : les déplacer dans la vue 3D, régler `radius`, `points`, `timeout` et
`capture_time` dans l'inspecteur, ou en ajouter / supprimer (instancier `zone_defense.tscn` sous
`ZoneDefenseMode`). Placement actuel : sur la ligne à égale distance des deux points d'apparition.

### Ajouter un niveau

1. Créer une scène dans `scenes/levels/` (décor uniquement, sans joueurs).
2. Remplacer l'instance `Arena` dans `scenes/game/game.tscn` par ce nouveau niveau,
   et ajuster la position des joueurs si besoin.
