extends Node
## Détection des parties hébergées sur le réseau local (annonces UDP).
##
## Tant qu'un ordinateur héberge, il diffuse une annonce toutes les
## BEACON_INTERVAL secondes. L'écran hôte/IP écoute ces annonces pour :
##   - interdire un deuxième hôte (NetworkManager.host() refuse) ;
##   - pré-remplir l'IP de l'hôte détecté.
## Best effort : certains réseaux (eduroam…) bloquent la diffusion ; dans ce cas
## rien n'est détecté et on saisit l'IP à la main, comme avant.

signal hosts_changed

const PORT := 7778
const BEACON_INTERVAL := 0.5
## Un hôte silencieux depuis plus longtemps est considéré comme parti.
const HOST_TIMEOUT := 2.0
const MAGIC := "BubbleShooter"

## Id de session de l'hôte -> { address: String, seen: float }.
var _hosts := {}
var _listener: PacketPeerUDP
var _sender := PacketPeerUDP.new()
## Permet d'ignorer nos propres annonces.
var _session_id := randi()
var _beacon_cooldown := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sender.set_broadcast_enabled(true)


## Commence à écouter les annonces (écran hôte/IP).
func start_listening() -> void:
	if _listener:
		return
	_listener = PacketPeerUDP.new()
	if _listener.bind(PORT) != OK:
		# Port déjà pris, typiquement par une 2e instance du jeu sur le même ordinateur.
		push_warning("LanDiscovery : impossible d'écouter le port %d, détection des hôtes désactivée." % PORT)
		_listener = null


func stop_listening() -> void:
	if _listener:
		_listener.close()
		_listener = null
	if not _hosts.is_empty():
		_hosts.clear()
		hosts_changed.emit()


## Adresses IP des hôtes détectés sur le réseau.
func get_hosts() -> PackedStringArray:
	var addresses := PackedStringArray()
	for host: Dictionary in _hosts.values():
		addresses.append(host.address)
	return addresses


func _process(delta: float) -> void:
	_beacon_cooldown -= delta
	if _beacon_cooldown <= 0.0:
		_beacon_cooldown = BEACON_INTERVAL
		if NetworkManager.is_online() and multiplayer.is_server():
			_send_beacon()
	if _listener:
		_receive_beacons()
		_forget_silent_hosts()


func _send_beacon() -> void:
	var packet := JSON.stringify({"magic": MAGIC, "id": _session_id}).to_utf8_buffer()
	# 127.0.0.1 : macOS ne se renvoie pas ses propres diffusions (tests à plusieurs instances).
	var targets := PackedStringArray(["255.255.255.255", "127.0.0.1"])
	for address in NetworkManager.get_local_ipv4_addresses():
		targets.append(_broadcast_address_of(address))
	for target in targets:
		_sender.set_dest_address(target, PORT)
		_sender.put_packet(packet)


func _receive_beacons() -> void:
	var changed := false
	while _listener.get_available_packet_count() > 0:
		var data = JSON.parse_string(_listener.get_packet().get_string_from_utf8())
		var address := _listener.get_packet_ip()
		if not data is Dictionary or data.get("magic") != MAGIC or data.get("id") == _session_id:
			continue
		var id: int = int(data.id)
		var known: Dictionary = _hosts.get(id, {})
		# La même annonce peut arriver par 127.0.0.1 et par le Wi-Fi : on garde l'IP réseau.
		if known.is_empty() or (known.address == "127.0.0.1" and address != "127.0.0.1"):
			changed = true
			known.address = address
		known.seen = _now()
		_hosts[id] = known
	if changed:
		hosts_changed.emit()


func _forget_silent_hosts() -> void:
	var changed := false
	for id: int in _hosts.keys():
		if _now() - _hosts[id].seen > HOST_TIMEOUT:
			_hosts.erase(id)
			changed = true
	if changed:
		hosts_changed.emit()


## Adresse de diffusion supposée du réseau de `address` (/28 pour un partage iPhone, /24 sinon).
static func _broadcast_address_of(address: String) -> String:
	if address.begins_with("172.20.10."):
		return "172.20.10.15"
	var parts := address.split(".")
	return "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
