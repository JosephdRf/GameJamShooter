# Duck my Life

Jeu Godot **4.7** **2v2 en réseau local** : 4 ordinateurs, chacun contrôle un canard,
caméra à la 3e personne. Un des joueurs héberge la partie (« listen server »).

## Parcours des écrans

| Écran | Scène | Mène à |
|-------|-------|--------|
| Chargement (fictif, 3 s, jauge d'eau `WaterGauge` + pourcentage) | `loading_screen.tscn` | Accueil |
| Accueil (titre « Duck my Life » qui flotte, « Fuck My Life » une fois sur dix, bouton jaune) | `title_screen.tscn` | **Démarrer** → Hôte/IP |
| Hôte/IP | `connect_screen.tscn` | Héberger → Sélection d'équipe · Rejoindre → connexion réussie ? oui : Sélection d'équipe, non : reste ici avec un message |
| Sélection d'équipe (une fois son joueur validé : fenêtre du pseudo, tout en majuscules, gardé pour la fois suivante, affiché sur le bouton à la place de « Joueur N » (sans pseudo, le joueur s'appelle « Joueur N », aussi au-dessus de son canard) ; en jeu, affiché au-dessus des canards des autres joueurs) | `team_select.tscn` | **Lancer la partie** (hôte) → Préparation du combat |
| Préparation du combat (8 s, sur tous les ordinateurs : rangée de bulles `BubbleBar` à la couleur de son équipe + pourcentage, fond noir ; en haut, deux planches « carnet d'inventeur » sur parchemin, le canard et son pistolet à bulles de face et de profil (`assets/ui/plates`) ; dessous, deux fiches de 4 s, « Le saviez-vous ? » sur l'histoire puis « Commandes » avec les touches du clavier ou de la manette utilisée (`InputBadge`) ; la scène de combat se charge en arrière-plan, est créée sur un autre fil, et l'arène est rendue une fois dans une vue cachée pour compiler ses shaders) | `match_loading.tscn` | GAME |
| GAME | `game/game.tscn` | Pause (hôte) · fin du combat → Écran de fin |
| Pause (dans GAME ; style des menus : jeu figé grisé derrière (`pause_dim.gdshader`), bulles, titre « Pause » qui flotte, bouton jaune « Reprendre », bulle « Quitter ») | `pause_menu.tscn` | Reprendre → GAME · Quitter → Sélection d'équipe (tout le monde) |
| Écran de fin (style des menus : serviettes bleue et rouge avec scores et pseudos, badge « Gagné ! ») | `end_screen.tscn` | **Rejouer** → Sélection d'équipe · **Quitter** → ferme le jeu |

Sur tous ces écrans, quelques bulles transparentes montent doucement derrière les textes et les boutons
(`RisingBubbles`, `scripts/ui/rising_bubbles.gd`, nœud `Bubbles` juste au-dessus du fond).

Chaque écran est une scène indépendante de `scenes/ui/` (script du même nom dans `scripts/ui/`).
Les chemins sont regroupés dans `scripts/ui/screens.gd` (`Screens.TITLE`, `Screens.GAME`…).

## Lancer une partie

1. **Même réseau** : tous les ordinateurs sur le même Wi-Fi. Le plus simple est le partage de
   connexion du téléphone de l'hôte (voir [Réseau](#réseau)).
2. L'hôte lance le jeu, appuie sur **Démarrer** puis **Héberger** (serviette bleue) : son adresse IP s'affiche.
   **Un seul hôte par réseau** : dès qu'une partie est détectée, « Héberger » est désactivé chez les autres.
3. Les autres lancent le jeu, appuient sur **Démarrer** : l'IP de l'hôte est pré-remplie si la partie
   est détectée (sinon la saisir), puis **Rejoindre**.
4. Chacun choisit son joueur avec le joystick gauche ou ← → (un joueur déjà pris par un autre ordinateur est grisé ; le sien est entouré de jaune, contour qui pulse jusqu'à la validation),
   puis valide avec **A** : le curseur passe sur « Lancer la partie ».
   Équipe bleue : J1 + J2 · Équipe rouge : J3 + J4 (couleurs dans `Player.TEAM_COLORS`).
5. L'hôte appuie sur **Start** (bouton +), ou A / Entrée sur « Lancer la partie » : la partie se lance pour tous,
   même s'il manque des joueurs (les canards non choisis restent immobiles).
   « **Attention…** » s'affiche 2 s (joueurs figés), puis « **C'est parti !** » : on peut bouger, le
   chrono et les zones démarrent.

6. En jeu, l'hôte peut mettre en pause (**P** ou **+**) : la partie est figée pour tous.
   « Quitter » ramène tout le monde à la sélection d'équipe.
7. Un **compte à rebours** (4:00 par défaut) est affiché en haut au centre, sur un nuage de bulles, entre
   les scores des deux équipes dans des bulles à leur couleur (`Scoreboard`, `scripts/ui/scoreboard.gd` :
   police Titan One, formes qui respirent ; un score qui augmente gonfle avec sa bulle ; dans les
   **20 dernières secondes** les chiffres passent au jaune et battent à chaque seconde). Il est figé pendant la
   pause. À 0:00, tout le monde passe à l'écran de fin, sauf si une zone est en cours de capture :
   **prolongation** (« Prolongation ! » 2 s, le 0:00 clignote) jusqu'à ce que la zone soit capturée
   ou que sa barre reparte à 0 (l'équipe est sortie). L'hôte fait foi : il envoie le temps restant
   aux autres toutes les 0,5 s. Durée réglable avec `match_duration` sur le nœud `Game`
   (0 = pas de limite, chrono masqué).
8. **Défense de zone** : aucune zone au début ; la première apparaît **5 s** après « C'est parti ! »
   (`first_zone_delay` sur `ZoneDefenseMode`), avec « Une nouvelle zone est apparue ! ». Ensuite, une
   seule zone (ronde, ou rectangulaire pour l'îlot central) est toujours active (tirée au hasard, jamais la
   même deux fois de suite). Une équipe qui y reste **seule 10 s** la capture et gagne **2 points** ;
   la zone prend la couleur de l'équipe présente et une barre de progression s'affiche sous le
   score. Au sol, un **disque** à la couleur de l'équipe (rectangle pour la zone rectangulaire) part du
   centre et atteint le bord à la capture ; son aire grandit à vitesse constante (à mi-capture, la moitié
   du sol est couverte), liseré clair sur son bord ; rayures qui défilent si la zone est disputée ; il se
   résorbe vite si l'équipe sort (`zone_floor.gdshader`). Une colonne de lumière de 30 m, parcourue de vagues qui montent (plus vite pendant une
   capture), dorée puis à la couleur de l'équipe qui capture (
   `beacon_height`) montre la zone active de loin. Un canard compte comme dedans tant que son corps touche la zone (même centré un peu
   hors du bord). Si l'équipe sort, la barre repart à 0 ; si les deux équipes sont dedans, elle est en
   pause. Une zone reste jusqu'à sa capture (pas de limite de temps) ; **5 s** après
   une capture, une autre apparaît, annoncée par « Une nouvelle zone est apparue ! » (`next_zone_delay`). Scores : bleu à gauche du chrono, rouge à droite. À chaque prise :
   « Ton équipe a pris la zone clé ! » ou « L'adversaire a pris la zone clé ! ».
9. Fin du combat : écran des scores de chaque équipe, **Rejouer** (retour à la sélection
   d'équipe) ou **Quitter** (ferme le jeu). Avant l'écran de fin, « Terminé ! » s'affiche 1,5 s,
   joueurs figés.

Dans l'éditeur : **F5** lance le jeu depuis l'écran de chargement, **F6** sur `scenes/game/game.tscn` lance le jeu seul
(hors ligne, on contrôle le joueur 1).

## Contrôles

Les actions se modifient dans **Projet › Paramètres du projet › Contrôles** (Input Map) : une action
par commande, avec sa touche clavier et son bouton de manette. Le code n'utilise que ces actions.

| Commande | Action | Clavier + trackpad | Switch Pro | PlayStation |
|----------|--------|--------------------|------------|-------------|
| Se déplacer | `move_left/right/up/down` | Z/Q/S/D (W/A/S/D en QWERTY) ou flèches | Stick gauche | Stick gauche |
| Tourner la caméra | `look_left/right/up/down` | Souris / trackpad | Stick droit | Stick droit |
| Sauter | `jump` | Espace | B | Croix |
| Dash (au sol, toutes les 2 s ; gauche / droite l'infléchissent) | `dash` | Maj | Y | Carré |
| Tirer une bulle (maintenir = en continu) | `shoot` | Clic gauche / T | ZR | R2 |
| Viser : la caméra zoome, sans aide à la visée (**désactivé pour l'instant** : aucune touche) | `aim` | — | — | — |
| Bulle de capture (toutes les 1 s, 20 % d'eau) | `capture` | Clic molette | R | R1 |
| Canon à eau (maintenir, prototype) | `water_cannon` | Clic droit | ZL / L | L2 / L1 |
| **Menus** : naviguer / choisir son joueur (4 directions) | `menu_left/right/up/down` (+ `ui_*` de Godot) | Flèches (Z/Q/S/D) | Stick gauche / croix | Stick gauche / croix |
| **Menus** : valider | `ui_accept` | Entrée / Espace | A | Rond |
| **Accueil** : démarrer ; **Sélection** : lancer la partie (hôte) | `start` | Entrée sur le bouton | + | Options |
| **Sélection** : changer de joueur après validation | `menu_back` | Retour arrière | B | Croix |
| **En jeu** : pause (hôte uniquement) | `pause` | P | + | Options |
| **Pause** : reprendre (hôte) | `pause` / `menu_back` / `ui_cancel` | P / Retour arrière / Échap | + / B | Options / Croix |
| **En jeu** : test, s'infliger 10 dégâts (version de développement) | `debug_damage` | H | — | — |
| **En jeu** : debug mode (PV, rectangle de l'aide à la visée), désactivé au lancement | `debug_mode` | Ctrl + D | — | — |
| Retour à l'écran précédent (menus) / quitter le jeu | `ui_cancel` | Échap | — | — |

La souris est capturée au lancement (curseur invisible) pour piloter la caméra.
Chaque ordinateur contrôle son canard au clavier/trackpad **ou** avec n'importe quelle manette branchée. Les déplacements sont relatifs à la caméra.
Un canard monte en marchant sur les reliefs de 55 cm au plus (`max_step_height`), sans sauter (les marches
du toboggan font 50 cm). Échelles (groupe `echelles` : une `Area3D` par échelle) : en avançant vers une échelle,
le canard monte le long de celle-ci à `climb_speed`.
Un joueur qui tombe de la plateforme meurt.

### Tir

- **Viseur** au centre de l'écran (`scenes/ui/crosshair.tscn`) : il se resserre et passe au rouge sur un
  adversaire. La caméra est placée façon Splatoon : derrière et au-dessus du canard, presque horizontale.
- **Aide à la visée** (`scripts/player/aim_assist.gd`, nœud `AimAssist` du joueur) : si un adversaire visible
  entre dans un rectangle de 200 × 150 px autour du centre de l'écran (affiché en debug mode, Ctrl + D),
  le viseur glisse vers lui sans bouger la caméra, et les bulles partent vers le viseur.
- **Visée** (action `aim` maintenue) : la caméra avance le long de son bras et resserre son champ
  (`aim_fov`, `aim_arm_length` sur `PlayerCamera`) ; l'aide à la visée est coupée, le viseur reste au centre.
- Chaque appui tire une bulle vers le point visé (aussi vers le haut ou le bas), avec au moins 0,15 s entre
  deux appuis ; touche maintenue, une bulle toutes les 0,2 s. Elle sort
  du bout du canon du canard, petite, et atteint sa taille en 0,12 s.
- La bulle éclate au premier contact : obstacle (sol, mur, objet…), joueur (**30 dégâts** à un adversaire,
  rien à un coéquipier), mur de la zone d'apparition adverse, ou au bout de **25 m**. Le nœud est alors supprimé.
  Sur un adversaire, elle fait une **grosse éclaboussure** (coque d'eau qui gonfle, gerbe de gouttes vers le
  tireur et gouttelettes tout autour : `Puddles.duck_splash`), pour qu'on voie qu'il a été touché.
- **Zones d'apparition** : un mur invisible (calques 3 « spawn_blue » / 4 « spawn_red ») empêche les joueurs
  et les bulles de l'équipe adverse d'y entrer.
- Réglages : sur `scenes/game/bubble_projectile.tscn` (`speed`, `max_distance`, `damage`, `friendly_fire`,
  taille du mesh = taille de la zone de contact) et sur le joueur (`fire_cooldown`, `auto_fire_interval`, groupe « Tir »).

### Capture

- **Clic molette** (action `capture`) : tire une grosse bulle, plus lente (18 m/s, **portée illimitée** : elle vole jusqu'à toucher quelque chose), au plus
  une par seconde ; elle coûte **20 %** de la réserve d'eau. Elle est aussi grosse que la bulle qui enferme un
  canard (1,54 m de rayon visible, 1 m de contact avec les canards) et roule au ras du sol (`visual_lift`).
- En éclatant (sur un canard, le décor…), elle **explose** : les adversaires à moins de **4 m** perdent de
  **30 PV** (au centre) à **10 PV** (au bord) ; un canard capturé (dont celui que la bulle vient de piéger) et les
  coéquipiers ne sont pas touchés (`explosion_radius`, `explosion_damage_max`, `explosion_damage_min`).
- Un adversaire touché est **piégé 2 s** dans une bulle à la couleur de l'équipe qui l'a eu : il décolle de
  25 cm puis **s'élève lentement** (1 m de plus en 2 s, en flottant ; il s'arrête sous un plafond) et ne peut
  plus bouger, sauter, dasher ni tirer (il peut toujours tourner la caméra et prendre des dégâts). Puis la bulle éclate et il retombe au sol. Rien sur un coéquipier ; un
  joueur déjà piégé ne l'est pas une 2e fois. Mort dans la bulle : elle disparaît.
- Réglages : `scenes/game/capture_bubble.tscn` (scène héritée de la bulle normale : `speed`,
  `max_distance`, `radius`, `world_radius` : rayon plus petit contre le décor pour qu'elle frôle le sol
  sans éclater, `capture_duration`) et sur le joueur, groupe « Capture » (`capture_cooldown`,
  `capture_lift`, `capture_rise`, `capture_bob`). Bulle autour du canard : nœud `CaptureBubble` de `player.tscn`.

### Plastron

- Plus de canard plastron dans la partie (retiré de `game.tscn`). Le code le permet toujours : une
  instance de joueur avec `Player.dummy` est l'adversaire de tout le monde (`get_team()` = 0), ne bouge
  pas, ne compte pas dans les zones et réapparaît au même endroit.

### Réserve d'eau

- Jauge **Eau** en bas à gauche (`MatchHud`, nœud `Water` : tube de `WaterGauge` dont l'eau ondule et fait
  des bulles, plus claire pendant la recharge ; pas de pourcentage). Un tir coûte **5 %**, une grosse bulle **20 %**,
  le jet **20 % par seconde**. Sans assez d'eau, rien ne part et la jauge clignote en rouge.
- Après **2 s** sans dépenser d'eau, elle se recharge de plus en plus vite (la vitesse double toutes les
  0,6 s) : pleine environ 4,5 s après le dernier tir, même vide. Pleine à la réapparition.
- Réglages : groupe « Eau » du joueur (`water_per_shot`, `water_per_capture`, `water_per_second`,
  `water_recharge_delay`, `water_recharge_rate`, `water_recharge_doubling`, `water_recharge_max_rate`).

### Canon à eau (prototype)

- **Clic droit maintenu** (action `water_cannon`) : jet d'eau continu vers le viseur. Les gouttes partent un peu vers
  le haut pour que leur arc retombe sur le point visé (comme un tuyau d'arrosage) ; une sur cinq, plus lente,
  retombe un peu avant. Là où le jet touche le sol, une flaque se forme et grandit (cf. Flaques). Chaque
  goutte qui touche un adversaire lui inflige **0,4 PV** (`damage_per_drop`), soit environ 56 PV/s si tout
  le jet le touche ; rien aux coéquipiers.
- Code : `scripts/game/water_cannon.gd` (nœud `WaterCannon` de `game.tscn` : débit, vitesse, gravité,
  dispersion, eau laissée au sol, taille des gouttes). Toutes les gouttes sont dessinées d'un coup
  (MultiMesh). Réseau : seuls « canon en marche » et le point visé sont envoyés ; chaque ordinateur
  simule les gouttes.

### Flaques (prototype)

- Une bulle qui éclate sur le sol (ou le dessus d'un meuble) laisse une **flaque d'eau** (rayon 2 m,
  10 m pour la maxi-bulle : `puddle_radius`), de forme irrégulière, qui s'étale du centre vers les bords
  en 0,3 s (`spread_time`). Deux flaques proches se rejoignent
  en une seule ; tirer plusieurs fois au même endroit l'agrandit.
- **Évaporation** : l'eau reste **1 min** après son dernier arrosage, puis pâlit et disparaît en **3 s**
  (`water_lifetime` = 63 s, `fade_duration`) ; réarroser une flaque la rafraîchit (groupe « Évaporation » du nœud `Puddles`).
- **Dash sur l'eau** : il ne s'use pas. Le canard garde sa vitesse tant qu'il glisse sur une flaque, et
  la distance du dash ne compte que sur le sol sec (`dash_slides_on_water` sur le joueur). Contre un mur,
  le dash se termine normalement.
- **L'eau réagit** : à chaque éclatement, des ronds dans l'eau et des gouttes ; un canard qui marche
  dedans fait un rond et un « splotch » à chaque pas (`WaterStepSound`), et laisse un sillage (ronds +
  gerbes) quand il glisse dessus.
- Code : `scripts/game/puddles.gd` (nœud `Puddles` de `game.tscn` : couleur, forme, résolution, budget de
  peinture par image). Rien n'est envoyé en réseau : chaque ordinateur fait éclater sa copie de la bulle
  au même endroit.

### Sèche-cheveux (prototype)

- Au centre d'`arena4` (au pied de la rampe de l'îlot central) : un sèche-cheveux allumé, debout au milieu d'un socle rond (liseré métal).
  Le jet est toujours actif : tout canard en l'air dans la colonne d'air chaud est porté vers le haut et
  flotte vers 13 m (en montant et descendant un peu : la puissance du souffle oscille) tant qu'il y reste ; il retombe en en sortant par le côté. Sauter
  depuis le socle lance l'envol (au lieu d'un saut de 2 m).
- Les bulles et les gouttes d'eau (canon à eau, éclaboussures) qui traversent la colonne d'air chaud
  montent (≈ 1 m pour une bulle qui la traverse ; les gouttes remontent au lieu de retomber) :
  `projectile_lift_speed`, `projectile_lift_acceleration` (`HairDryer.lift_projectile`).
- Air chaud visible (jet, colonne en voile transparent qui laisse voir les bulles, filets d'air, lueur de la buse) et audible.
  L'air est blanc neutre (`air_color`) pour ne pas être confondu avec les zones à défendre, colorées.
- Scène `scenes/game/hair_dryer.tscn` (à poser n'importe où), script `scripts/game/hair_dryer.gd` : `zone_radius`,
  `launch_speed`, `updraft_speed`, `lift_acceleration`, `lift_gravity`, `column_height`, `hover_height`, `power_variation`, `power_period`, `air_color`. Shader : `assets/shaders/hot_air.gdshader`.

### Vie

- Chaque joueur a **100 PV**. Pas de barre de vie : plus il en a perdu, plus l'écran se couvre de bulles,
  autour d'une ellipse dégagée au centre (3 écrans de dégâts : 100→67, 67→33, 33→0 PV ; les grosses
  bulles n'arrivent qu'avec le 3e). Les bulles restent en place, grossissent quand on perd des PV et
  rétrécissent jusqu'à disparaître quand on en regagne.
- Sans dégâts pendant 2 s, la vie remonte de **10 PV/s**.
- À 0 PV : l'écran passe en gris avec « Tu es mort » ; le canard joue son animation de mort (`death` de
  `duck_v4.glb`, état `death` de l'AnimationTree : il bascule sur le dos, pattes en l'air, et retombe au sol
  s'il était en l'air), disparaît dans un pop de bulle, puis il réapparaît 2 s après sa mort sur sa
  zone d'apparition avec 100 PV.
- Chez le tireur, en bas de l'écran à droite de la jauge d'eau : « Vous avez éliminé ROMEO ! +1 » (+1 en jaune : chaque élimination d'un adversaire rapporte
  **1 point** à l'équipe, `ZoneDefenseMode.kill_points` ; « Joueur 3 » sans
  pseudo), 2,5 s, avec un son d'élimination (pop de bulle + arpège de clochettes, `sfx/kill/kill.wav`).
- Fil des éliminations en haut à droite (`scripts/ui/kill_feed.gd`) : « ROMEO a éclaté EDOUARD », pseudos aux
  couleurs des équipes, « Edouard est tombé » sans tireur ; entouré de jaune quand ça concerne son joueur.
  Chaque dégât porte le joueur qui a tiré (`take_damage(amount, attacker_id)`), annoncé à tous à la mort
  (signal `Player.eliminated`).
- Pour infliger des dégâts (futures armes) : `player.take_damage(montant)`, depuis n'importe quel ordinateur.
- Réglages (inspecteur du joueur, groupe « Vie ») : `max_health`, `regen_rate`, `regen_delay`, `respawn_delay`.

### Sons

- Chaque événement tire un son au hasard (jamais le même deux fois de suite), un peu plus aigu ou
  grave à chaque fois : ressources `AudioStreamRandomizer` de `assets/audio/sfx/*.tres`, qui piochent
  dans le dossier du même nom (`shoot/`, `pop/`, `step/`…). Les sons sont découpés et calés sur leur
  attaque : ils partent pile au moment de l'action.
- Canard (nœuds `*Sound` de `player.tscn`, entendus sur tous les ordinateurs, en 3D) : tir, **pas calés sur
  l'animation** (instants où un pied se pose : `Player.FOOTSTEPS`), dash, saut (décollage) et atterrissage (après un saut ou une chute), touché (canard en
  caoutchouc), mort (coin-coin), réapparition. Bulle : éclatement (`PopSound` de `bubble_projectile.tscn`).
- Zone capturée : gamme montante (`CaptureSound` de `game.tscn`, `sfx/capture/`), entendue partout.
- **Montée de capture** : pendant une capture, une clochette monte la gamme note après note (une note par
  seconde au début, environ cinq à la fin, 27 notes en 10 s), au rythme de la barre : elle se fige quand la zone
  est disputée et repart du début si l'équipe sort. Son 3D au centre de la zone : plein volume à moins de 8 m,
  de plus en plus discret au-delà, inaudible à 60 m (`ZoneDefense`, groupe « Montée de capture » ;
  `sfx/capture/capture_note.wav`). La gamme « Zone capturée » prend le relais.
- Nouvelle zone (la première, puis 5 s après chaque capture) : la même gamme, plus grave
  (`NewZoneSound`, `sfx/capture/zone_appeared.wav`), entendue partout. Les deux sons ont de la réverbération.
- Menus : autoload `UiSounds` (clic en naviguant, « plop » en validant), branché sur tous les boutons.
- Musique : autoload `Music` (`play(...)` dans le `_ready()` de chaque écran ; changement en fondu).
  Menus : `music/musique_menus.mp3` (1 min 17, en boucle), sans se relancer d'un écran à l'autre, et reprend
  là où elle s'était arrêtée après un combat.
  Combat : `music/musique_combat.mp3` (4 min 48, en boucle), depuis le début à chaque partie, à -19 dB car
  mixée bien plus fort (`Music.VOLUMES_DB`).
- Volume : `volume_db` de chaque nœud `*Sound` ; variation : `random_pitch` des `.tres`.
- Sources : `sfx/bubble/` (Pixabay), `sfx/duck/` et `sfx/freesound/` (Freesound, CC0, voir `CREDITS.txt`),
  `sfx/jump/` et `sfx/land/` (saut sur béton : décollage et réception, La Sonothèque, voir `CREDITS.txt`),
  `sfx/capture/` (« scale-c6 », freesound_community, Pixabay ; baissé de 3 et 7 demi-tons, réverbération).
- **Testeur** : `python tools/sfx_tester/build_sfx_tester.py` puis ouvrir `tools/sfx_tester/sfx_tester.html`
  pour écouter tous les sons du jeu (et des candidats Freesound) et simuler des tirs.

> **Note sur les boutons :** Godot repère les boutons de manette par leur *position* (noms Xbox) : un même réglage vaut pour toutes les manettes. Bouton du **bas** (`Joypad Button 0`) = B sur Switch Pro, Croix sur PlayStation, A sur Xbox ; bouton de **droite** (`1`) = A / Rond / B ; bouton de **gauche** (`2`) = Y / Carré / X ; gâchettes = axes 4 et 5.

> **Manettes qui envoient de fausses valeurs** (vu avec une Switch Pro sous macOS : stick gauche annoncé
> poussé et ZR enfoncée alors que personne n'y touche) : `InputManager` ne prend en compte un axe d'une
> manette (stick ou gâchette) qu'une fois vu au repos. Sinon le canard avancerait ou tirerait tout seul.
> Les boutons de cette manette marchent toujours ; la débrancher / rebrancher relance la vérification.

## Architecture

```
.
├── project.godot            # Configuration (scène de départ, autoloads, plein écran…)
├── addons/godot_ai_mcp/     # Plugin éditeur MCP (pilotage de l'éditeur par une IA)
├── assets/                  # Ressources brutes, importées par Godot
│   ├── themes/ui_theme.tres # Thème commun à tous les écrans (taille de police…)
│   ├── fonts/titan_one/     # Police Titan One (licence OFL) : titres, menus, annonces, chrono, HUD
│   ├── audio/{music,sfx}/   # sfx/*.tres : sons tirés au hasard dans sfx/<nom>/ (cf. Sons)
│   ├── fonts/
│   ├── icons/               # icon.png (icône du projet : rendu du canard bleu)
│   ├── materials/           # duck_*.tres : matériaux texturés du canard (corps, pistolet, réservoir bleu/rouge)
│   ├── models/              # bain-de-coin-coin.blend : l'arène (importée via Blender) ; duck_v4.glb : le canard
│   └── textures/            # Textures du canard (diffuse / normal / roughness)
├── scenes/                  # Scènes (.tscn), un sous-dossier par domaine
│   ├── ui/                  # Un fichier par écran, modifiable indépendamment
│   │   ├── loading_screen.tscn  # Écran de chargement (scène de départ)
│   │   ├── match_loading.tscn   # Préparation du combat (8 s, entre la sélection d'équipe et le combat)
│   │   ├── title_screen.tscn    # Écran d'accueil : « Duck my Life » + Démarrer
│   │   ├── connect_screen.tscn  # Écran hôte/IP (style sélection d'équipe) : Héberger / IP + Rejoindre / Quitter
│   │   ├── team_select.tscn     # Sélection d'équipe (choix des joueurs)
│   │   ├── match_hud.tscn       # HUD en jeu : chrono et scores (Scoreboard), capture, eau (instancié dans game.tscn)
│   │   ├── pause_menu.tscn      # Menu pause (instancié dans game.tscn)
│   │   ├── end_screen.tscn      # Écran de fin : serviettes avec scores et pseudos, équipe gagnante, Rejouer / Quitter
│   │   ├── death_screen.tscn    # « Tu es mort » + image grisée (instancié dans game.tscn)
│   │   ├── announcer.tscn       # Messages de match (Attention…, C'est parti !, zone, Prolongation !, Terminé !), style Splatoon, effet au choix (`effect` : Splat, Slide, Stamp, Flash, Jelly)
│   │   ├── crosshair.tscn       # Viseur (rouge sur un adversaire)
│   │   ├── damage_overlay.tscn  # Regroupe les écrans de dégâts (instancié dans game.tscn)
│   │   └── damage/damage_screen_1..3.tscn  # Bulles sur les bords, de plus en plus couvrantes
│   ├── game/game.tscn       # Partie : Arena + Players/Player1..4 + SpawnZones (2) + Projectiles + ZoneDefenseMode (4 zones) + MatchHud + PauseMenu
│   ├── game/zone_defense.tscn   # Une zone à capturer (rayon, points, timeout, durée de capture)
│   ├── game/zone_spawn.tscn     # Zone d'apparition d'une équipe (équipe, rayon)
│   ├── game/bubble_projectile.tscn  # Bulle tirée (vitesse, portée, dégâts)
│   ├── levels/arena.tscn    # Salle de bain (.blend) + lumières + barrière invisible devant
│   └── player/
│       ├── player.tscn          # Scène de base : canard (assets/models/duck_v4.glb) + AnimationTree + caméra + synchro réseau
│       ├── player_1.tscn … player_4.tscn  # Une scène héritée par joueur (id → couleur, équipe)
│       └── player_camera.tscn   # Caméra 3e personne (SpringArm3D)
└── scripts/                 # Scripts GDScript, même découpage que scenes/
    ├── autoload/input_manager.gd    # Liste des actions ; filtre les axes des manettes défaillantes
    ├── autoload/network_manager.gd  # Héberger/rejoindre, joueurs, lancement, pause, fin de combat
    ├── autoload/lan_discovery.gd    # Annonce/détection de l'hôte sur le réseau local (UDP 7778)
    ├── autoload/ui_sounds.gd        # Sons des menus (clic, validation), branchés sur tous les boutons
    ├── autoload/music.gd            # Musique de fond (boucle des menus), en fondu d'un écran à l'autre
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
  hôte/IP l'écoute, grise « Héberger » et pré-remplit l'IP. Si le réseau bloque la diffusion,
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
- Les actions d'entrée sont définies dans Projet › Paramètres du projet › Contrôles (section `[input]` de
  `project.godot`) ; le code n'utilise que celles-ci (liste en tête de `scripts/autoload/input_manager.gd`).
  Pas de touche ni de bouton écrits en dur dans le code.
- Changer d'écran : `get_tree().change_scene_to_file(Screens.XXX)` (sauf les transitions
  réseau, faites par `NetworkManager` pour que tous les ordinateurs suivent).
- Calques physiques : 1 = `world`, 2 = `players`.

### L'arène salle de bain

- **Arène du jeu : `scenes/levels/arena5.tscn`** (modèle Blender `assets/models/arene_bain/arene_bain.glb`,
  éclairage `scenes/levels/eclairage_arene.tscn`, collisions ajoutées par `scripts/levels/arena5.gd` et
  `tools/arena_glb_post_import.gd`). Même plan qu'`arena4` (maquette) : zone d'apparition bleue sous la
  planche à repasser (ouest), rouge sur la marche du placard (est) ; zones de défense sur le matelas gonflable
  de la baignoire (11 m), le dessus du panier à linge (7,2 m, rectangle, ex-îlot central), le rebord de
  fenêtre sous le lavabo (6,2 m) et le sol de la douche . L'ancienne arène
  ci-dessous (`arena.tscn`, `arena4.tscn`) reste dans le projet.
- Collisions d'`arena5` légères, choisies à l'import par `tools/arena_glb_post_import.gd` : forme exacte pour
  la structure (sol, murs, plafond, marches), boîtes pour les objets en pavé (serviettes, magazines…), forme
  simplifiée (~400 triangles) pour les objets creux (baignoire, placard, matelas, planche à repasser,
  tabouret…), coque convexe pour le reste, rien pour l'eau et les petits objets (< 1 m). Environ 10 000
  triangles au total (370 000 avant). Le panier à linge (renversé) garde 3 000 triangles, sans son rebord
  au sol, pour qu'on entre dessous par le grand trou et les deux poignées ; son dessus, comme celui du
  carton voisin (où l'on entre aussi par deux trous), est une boîte plate (`TOP_BOX`) pour y marcher sans
  accrocher. Le même script retire les 4 barres
  du tabouret entre les pieds (rendu et collision, `REMOVED_PARTS`), pour passer dessous. La bouée oiseau
  (`Bouee_Detail`) a une forme simplifiée (plus de coque convexe) ; la serviette pliée en pente
  (`Serviette_005`) a une coque prolongée jusqu'au sol (`RAMPS`) : on y monte sans sauter. Après modification
  du script : réimporter `arene_bain.glb`.

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

### Le canard et ses animations

- Modèle `assets/models/duck_v4.glb` (exporté de Blender avec son armature `Duck_Rig`) ; textures
  appliquées par `player.gd` avec les matériaux `assets/materials/duck_*.tres` (réservoir, tuyau et
  ceinture en `duck_container_blue` / `duck_container_red` selon l'équipe).
- `idle`, `walk`, `run`, `walk_back`, `walk_left` et `walk_right` sont mises en boucle dans les options
  d'import du `.glb` (double-clic sur le fichier › onglet Animation › Loop Mode).
- Le nœud `AnimationTree` de `player.tscn` est une machine à états : sélectionner le nœud pour
  l'ouvrir dans le panneau du bas. Les transitions (fondus, priorités) se règlent en cliquant sur les
  flèches. `player.gd` ne fait que renseigner les conditions : `idle` / `walk` / `run` selon la
  vitesse (`MOVING_SPEED`, `RUN_SPEED`), `dashing` pendant le dash puis `dash_over`.
- L'état `walk` est un BlendSpace2D : `walk` (avant), `walk_back`, `walk_left`, `walk_right`. En posture
  de combat (pendant le tir, la visée et 0,6 s après), le canard regarde là où il vise ; il joue la
  marche qui correspond à sa direction (reculer, pas de côté), même à pleine vitesse. Sinon il regarde
  où il va : marche avant, ou `run` au-delà de `RUN_SPEED`.
- Dash : `dash_start` est jouée en 0,2 s (timeline personnalisée de son nœud, la moitié de
  `dash_duration`), puis `dash` en boucle jusqu'à la fin du dash, puis `dash_end` avant de revenir à
  la marche. Le début du dash est envoyé aux autres ordinateurs (RPC `_play_dash`).

### Régler les zones

Dans `scenes/game/game.tscn`, les zones sont les enfants de `ZoneDefenseMode`
(`ZoneDefense1` à `ZoneDefense4`, numérotées du côté bleu au côté rouge) : les déplacer dans la vue 3D
(centre au niveau du sol), régler `shape` (rond : `radius`, 6 m par défaut ; rectangle : `size`),
`points`, `timeout` et `capture_time` dans l'inspecteur, ou en ajouter / supprimer (instancier
`zone_defense.tscn` sous `ZoneDefenseMode`). `ZoneDefense2` est un rectangle qui couvre tout le
dessus de l'îlot central.

### Ajouter un niveau

1. Créer une scène dans `scenes/levels/` (décor uniquement, sans joueurs).
2. Remplacer l'instance `Arena` dans `scenes/game/game.tscn` par ce nouveau niveau,
   et ajuster la position des joueurs si besoin.
