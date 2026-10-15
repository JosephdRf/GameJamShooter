class_name Screens
## Chemins des écrans, dans l'ordre du parcours du joueur :
##
##   LOADING -> TITLE -> CONNECT -> TEAM_SELECT -> MATCH_LOADING -> GAME (+ menu pause) -> END
##                          ^------- échec ----'       ^---------------- Rejouer ----------------'
##
## Chaque écran est une scène autonome de scenes/ui/ (script dans scripts/ui/) :
## on peut en modifier un sans toucher aux autres. Le menu pause n'est pas un
## écran : il est instancié dans scenes/game/game.tscn.

const LOADING := "res://scenes/ui/loading_screen.tscn"
const TITLE := "res://scenes/ui/title_screen.tscn"
const CONNECT := "res://scenes/ui/connect_screen.tscn"
const TEAM_SELECT := "res://scenes/ui/team_select.tscn"
const MATCH_LOADING := "res://scenes/ui/match_loading.tscn"
const GAME := "res://scenes/game/game.tscn"
const END := "res://scenes/ui/end_screen.tscn"
