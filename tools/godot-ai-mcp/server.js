#!/usr/bin/env node
// Pont MCP (stdio) <-> plugin Godot "Godot AI MCP" (TCP 127.0.0.1:6505, JSON par ligne).
// Aucune dépendance : nécessite seulement Node.js 18+.
'use strict';
const net = require('net');
const readline = require('readline');

const HOST = process.env.GODOT_MCP_HOST || '127.0.0.1';
const PORT = parseInt(process.env.GODOT_MCP_PORT || '6505', 10);
const TIMEOUT_MS = 30000;

const S = (type, description) => ({ type, description });
const OBJ = (props, required = []) => ({ type: 'object', properties: props, required });
const ANY = d => ({ description: d });

// Outils exposés à Claude, calqués sur les méthodes du plugin (mcp_server.gd)
const TOOLS = [
  ['get_editor_status', "État de l'éditeur Godot (scène ouverte, projet en cours…).", OBJ({})],
  ['open_scene', 'Ouvre une scène dans l’éditeur.', OBJ({ scene_path: S('string', 'ex. res://scenes/levels/arena.tscn') }, ['scene_path'])],
  ['save_scene', 'Enregistre la scène ouverte.', OBJ({})],
  ['run_project', 'Lance le projet ou une scène précise.', OBJ({ scene_path: S('string', 'optionnel, res://...') })],
  ['stop_project', 'Arrête le jeu en cours.', OBJ({})],
  ['get_editor_logs', 'Dernières lignes de logs de l’éditeur.', OBJ({ line_count: S('integer', 'défaut 50') })],
  ['get_editor_output', 'Dernières lignes du panneau Output.', OBJ({ line_count: S('integer', 'défaut 50') })],
  ['get_scene_tree', 'Arbre des nœuds de la scène ouverte.', OBJ({ max_depth: S('integer', '-1 = illimité') })],
  ['get_node_info', 'Propriétés détaillées d’un nœud.', OBJ({ node_path: S('string', 'chemin relatif à la racine, ex. Structure/Sol') }, ['node_path'])],
  ['create_node', 'Crée un nœud (annulable avec Ctrl+Z). Vecteurs : {"x":..,"y":..,"z":..}, couleurs : {"r":..,"g":..,"b":..}.',
    OBJ({ parent_path: S('string', 'chemin du parent ("" = racine)'), node_type: S('string', 'ex. CSGBox3D'), node_name: S('string', 'nom'),
      properties: S('object', 'propriétés initiales, ex. {"size":{"x":1,"y":1.6,"z":0.06},"position":{"x":0,"y":0.8,"z":0}}') }, ['node_type'])],
  ['modify_node_property', 'Modifie une propriété d’un nœud.', OBJ({ node_path: S('string', ''), property: S('string', 'ex. position, size, operation'), value: ANY('nouvelle valeur') }, ['node_path', 'property', 'value'])],
  ['delete_node', 'Supprime un nœud.', OBJ({ node_path: S('string', '') }, ['node_path'])],
  ['reparent_node', 'Change le parent d’un nœud.', OBJ({ node_path: S('string', ''), new_parent_path: S('string', '') }, ['node_path', 'new_parent_path'])],
  ['connect_signal', 'Connecte un signal.', OBJ({ source_path: S('string', ''), signal_name: S('string', ''), target_path: S('string', ''), method_name: S('string', '') }, ['source_path', 'signal_name', 'target_path', 'method_name'])],
  ['get_node_connections', 'Liste les connexions de signaux d’un nœud.', OBJ({ node_path: S('string', '') }, ['node_path'])],
  ['create_primitive_mesh', 'Crée un MeshInstance3D primitif (box, sphere, cylinder, capsule, plane…).',
    OBJ({ parent_path: S('string', ''), mesh_type: S('string', 'box|sphere|cylinder|capsule|plane|...'), node_name: S('string', ''), size: ANY('taille {"x","y","z"} pour box'), radius: S('number', ''), height: S('number', ''), material_path: S('string', 'res://...tres') })],
  ['create_collision_shape', 'Crée un CollisionShape3D.', OBJ({ parent_path: S('string', ''), shape_type: S('string', 'box|sphere|capsule|cylinder'), node_name: S('string', ''), size: ANY('taille'), radius: S('number', ''), height: S('number', '') })],
  ['execute_gdscript', 'Exécute du GDScript dans l’éditeur (corps d’une fonction _run, peut faire return).', OBJ({ code: S('string', 'code GDScript') }, ['code'])],
  ['create_script', 'Crée un script et peut l’attacher à un nœud.', OBJ({ script_path: S('string', 'res://scripts/...gd'), content: S('string', ''), attach_to: S('string', 'chemin du nœud, optionnel') }, ['script_path', 'content'])],
  ['read_script', 'Lit un script.', OBJ({ script_path: S('string', '') }, ['script_path'])],
  ['get_input_actions', 'Liste les actions d’entrée du projet.', OBJ({})],
  ['add_input_action', 'Ajoute une action d’entrée.', OBJ({ action: S('string', ''), deadzone: S('number', ''), keys: S('array', 'ex. ["W","Space"]'), mouse_buttons: S('array', 'ex. [1]') }, ['action'])],
  ['set_project_setting', 'Modifie un paramètre du projet.', OBJ({ setting: S('string', ''), value: ANY('valeur') }, ['setting', 'value'])],
  ['create_material', 'Crée un StandardMaterial3D enregistré en .tres.', OBJ({ save_path: S('string', 'res://...tres'), albedo_color: ANY('"#ff0000" ou {"r","g","b"}'), roughness: S('number', ''), metallic: S('number', ''), emission_color: ANY(''), emission_energy_multiplier: S('number', '') }, ['save_path'])],
  ['get_viewport_screenshot', 'Capture la vue de l’éditeur.', OBJ({ viewport: S('string', '"3d" ou "2d"') })],
  ['api_lookup', 'Documentation d’une classe Godot (ClassDB).', OBJ({ class_name: S('string', 'ex. CSGBox3D'), include_inherited: S('boolean', '') }, ['class_name'])],
  ['list_project_files', 'Liste les fichiers du projet.', OBJ({ directory: S('string', 'res://'), extensions: S('array', 'ex. ["tscn"]'), recursive: S('boolean', ''), max_files: S('integer', '') })],
].map(([name, description, inputSchema]) => ({ name, description, inputSchema }));

// ---- connexion TCP vers Godot ----
let sock = null, buf = '', nextId = 1;
const pending = new Map();
function connect() {
  return new Promise((resolve, reject) => {
    if (sock && !sock.destroyed) return resolve(sock);
    const s = net.createConnection({ host: HOST, port: PORT }, () => { sock = s; resolve(s); });
    s.setEncoding('utf8');
    s.on('data', d => {
      buf += d; let i;
      while ((i = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, i).trim(); buf = buf.slice(i + 1);
        if (!line) continue;
        try { const msg = JSON.parse(line); const p = pending.get(msg.id); if (p) { pending.delete(msg.id); p(msg); } } catch (e) { log('réponse illisible: ' + line.slice(0, 200)); }
      }
    });
    s.on('error', e => { if (sock !== s) reject(e); log('TCP: ' + e.message); });
    s.on('close', () => { if (sock === s) sock = null; buf = ''; for (const [, p] of pending) p({ error: { message: 'Connexion à Godot fermée' } }); pending.clear(); });
  });
}
async function callGodot(method, params) {
  let s;
  try { s = await connect(); }
  catch (e) { return { error: { message: `Impossible de joindre Godot sur ${HOST}:${PORT}. Godot est-il ouvert avec le plugin "Godot AI MCP" activé ? (${e.message})` } }; }
  const id = nextId++;
  return new Promise(resolve => {
    const t = setTimeout(() => { pending.delete(id); resolve({ error: { message: 'Délai dépassé (Godot ne répond pas)' } }); }, TIMEOUT_MS);
    pending.set(id, msg => { clearTimeout(t); resolve(msg); });
    s.write(JSON.stringify({ id, method, params: params || {} }) + '\n');
  });
}

// ---- protocole MCP (JSON-RPC 2.0 sur stdio) ----
function log(m) { process.stderr.write('[godot-ai-mcp] ' + m + '\n'); }
function send(o) { process.stdout.write(JSON.stringify(o) + '\n'); }
const rl = readline.createInterface({ input: process.stdin });
rl.on('line', async line => {
  if (!line.trim()) return;
  let req; try { req = JSON.parse(line); } catch { return; }
  const { id, method, params } = req;
  if (id === undefined || id === null) return; // notifications
  try {
    if (method === 'initialize') {
      send({ jsonrpc: '2.0', id, result: { protocolVersion: (params && params.protocolVersion) || '2024-11-05', capabilities: { tools: {} }, serverInfo: { name: 'godot-ai-mcp', version: '1.0.0' } } });
    } else if (method === 'ping') {
      send({ jsonrpc: '2.0', id, result: {} });
    } else if (method === 'tools/list') {
      send({ jsonrpc: '2.0', id, result: { tools: TOOLS } });
    } else if (method === 'tools/call') {
      const name = params.name;
      if (!TOOLS.find(t => t.name === name)) return send({ jsonrpc: '2.0', id, result: { isError: true, content: [{ type: 'text', text: 'Outil inconnu : ' + name }] } });
      const r = await callGodot(name, params.arguments || {});
      if (r.error) return send({ jsonrpc: '2.0', id, result: { isError: true, content: [{ type: 'text', text: JSON.stringify(r.error) }] } });
      const res = r.result;
      if (res && res.image_base64) {
        const { image_base64, ...rest } = res;
        return send({ jsonrpc: '2.0', id, result: { content: [{ type: 'image', data: image_base64, mimeType: res.mime_type || 'image/png' }, { type: 'text', text: JSON.stringify(rest) }] } });
      }
      send({ jsonrpc: '2.0', id, result: { content: [{ type: 'text', text: JSON.stringify(res, null, 2) }] } });
    } else {
      send({ jsonrpc: '2.0', id, error: { code: -32601, message: 'Méthode non gérée : ' + method } });
    }
  } catch (e) {
    send({ jsonrpc: '2.0', id, error: { code: -32603, message: String(e && e.message || e) } });
  }
});
log(`prêt, cible Godot ${HOST}:${PORT}`);
