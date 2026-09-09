extends Node3D
## Visor de depuración de las velas físicas. Pinta encima de la escena, en vivo, quién sujeta
## cada vértice y qué aristas se estiran, para poder verlo CON MOVIMIENTO.
##
## Teclas:
##   F3  encender / apagar
##   F4  siguiente vista
##   F5  ver a través de la geometría (sin test de profundidad)
##
## Vistas:
##   0 ESTIRAMIENTO  cada arista con color según cuánto se ha estirado respecto a su reposo
##                   (azul = comprimida, verde = en reposo, amarillo = +12 %, rojo = +25 %).
##                   Las 12 peores llevan una cruz blanca en cada punta.
##   1 ANCLAJES      rojo = vértice fijado ; verde = libre. La línea magenta va del vértice
##                   simulado a donde su ancla le manda estar: si es larga, algo tira de él.
##   2 HUESOS        color según el hueso que más pesa en cada vértice.
##   3 OBSTÁCULOS    cápsulas de las perchas y flecha del viento. El panel dice si la vela
##                   lleva esa capa en su máscara (si no, las cápsulas NO la tocan).
##
## Se cuelga del barco. Encuentra solo las velas que expongan datos_depuracion().

@export var encendido := false
@export_range(0, 3) var vista := 0
@export var ver_a_traves := false
@export_range(0.0, 1.0) var aviso_estiramiento := 0.25  ## Rojo a partir de este estiramiento.
@export var tam_cruz := 0.06

const NOMBRES := ["ESTIRAMIENTO", "ANCLAJES", "HUESOS", "OBSTACULOS"]
const COLOR_HUESO := {
	"raiz": Color(1, 1, 1),
	"vela": Color(0.2, 0.9, 1),
	"driza": Color(1, 0.85, 0.1),
	"driza_pico": Color(1, 0.3, 1),
	"driza_foque": Color(0.4, 1, 0.4),
	"timon": Color(1, 0.5, 0),
}

var _velas: Array = []
var _mi: MeshInstance3D
var _im: ImmediateMesh
var _mat: StandardMaterial3D
var _lbl: Label
var _panel: PanelContainer
var _barco: Node3D
## Modo volcado: mide y escribe al log sin dibujar nada, para poder diagnosticar por CLI
## sin capturas. Se activa con:  godot --path . --headless --quit-after 600 -- volcar
var _solo_log := false
var _t_log := 0.0
## Modo captura: espera a que la vela esté izada y asentada, encuadra la mayor desde sotavento
## y guarda PNG. Se activa con:  godot --path . --quit-after 900 -- captura
var _captura := false
var _t_cap := 0.0
var _cap_hecha := false


func _ready() -> void:
	_montar.call_deferred()


func _buscar_barco() -> Node3D:
	var n := get_parent()
	while n != null:
		if n is CharacterBody3D:
			return n as Node3D
		n = n.get_parent()
	return get_parent() as Node3D


func _montar() -> void:
	_barco = _buscar_barco()
	if _barco == null:
		return
	for n in _barco.find_children("*", "Node3D", true, false):
		if n.has_method("datos_depuracion"):
			_velas.append(n)

	_im = ImmediateMesh.new()
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.disable_receive_shadows = true
	_mi = MeshInstance3D.new()
	_mi.name = "DepuraVelaDibujo"
	_mi.mesh = _im
	_mi.top_level = true                 # así puedo empujar coordenadas GLOBALES tal cual
	_mi.transform = Transform3D()
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Sin AABB propio, el dibujo se recorta en cuanto el barco se aleja del origen.
	_mi.custom_aabb = AABB(Vector3(-2000, -2000, -2000), Vector3(4000, 4000, 4000))
	add_child(_mi)

	var capa := CanvasLayer.new()
	capa.layer = 50
	add_child(capa)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.position = Vector2(-580, 8)
	_panel.custom_minimum_size = Vector2(570, 0)
	capa.add_child(_panel)
	_lbl = Label.new()
	_lbl.add_theme_font_size_override("font_size", 13)
	_panel.add_child(_lbl)

	_solo_log = OS.get_cmdline_user_args().has("volcar")
	_captura = OS.get_cmdline_user_args().has("captura")
	if _solo_log:
		encendido = true
	print("depurar_vela: %d velas encontradas.%s" % [_velas.size(),
		"  MODO VOLCADO" if _solo_log else "  F3 enciende, F4 cambia de vista."])
	_aplicar_visibilidad()


func _aplicar_visibilidad() -> void:
	if _mi != null:
		_mi.visible = encendido
	if _panel != null:
		_panel.visible = encendido
	if _mat != null:
		_mat.no_depth_test = ver_a_traves


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	var k := (e as InputEventKey).keycode
	if k == KEY_F3:
		encendido = not encendido
		_aplicar_visibilidad()
	elif k == KEY_F4 and encendido:
		vista = (vista + 1) % NOMBRES.size()
	elif k == KEY_F5 and encendido:
		ver_a_traves = not ver_a_traves
		_aplicar_visibilidad()


func _linea(a: Vector3, b: Vector3, c: Color) -> void:
	if _solo_log:
		return
	_im.surface_set_color(c)
	_im.surface_add_vertex(a)
	_im.surface_set_color(c)
	_im.surface_add_vertex(b)


func _cruz(p: Vector3, r: float, c: Color) -> void:
	_linea(p - Vector3(r, 0, 0), p + Vector3(r, 0, 0), c)
	_linea(p - Vector3(0, r, 0), p + Vector3(0, r, 0), c)
	_linea(p - Vector3(0, 0, r), p + Vector3(0, 0, r), c)


## Verde en reposo -> amarillo -> rojo al estirarse ; azul si se comprime.
func _color_estiramiento(f: float) -> Color:
	if f < 0.0:
		return Color(0.1, 0.4, 1).lerp(Color(0.1, 0.9, 0.2), clampf(1.0 + f, 0.0, 1.0))
	if f < 0.5:
		return Color(0.1, 0.9, 0.2).lerp(Color(1, 0.9, 0.1), f * 2.0)
	return Color(1, 0.9, 0.1).lerp(Color(1, 0.1, 0.1), (f - 0.5) * 2.0)


func _process(dt: float) -> void:
	# Antes del guardia de 'encendido': la captura se hace con el visor APAGADO.
	if _captura and not _cap_hecha:
		_t_cap += dt
		if _t_cap >= 9.0:      # izada (unos 5 s) más margen para que el paño se asiente
			_cap_hecha = true
			_capturar()
		return

	if not encendido or _im == null:
		return

	if _solo_log:
		_t_log += dt
		if _t_log < 2.0:
			return
		_t_log = 0.0
		# TIME_PHYSICS_PROCESS no se refresca por paso de fisica: hay que muestrearlo una vez
		# por frame de render, que es justo donde estamos.
		var salida := "\n===== t=%.1f s   viento fuerza %.2f   fisica %.3f ms   fps %d =====" % [
			Time.get_ticks_msec() / 1000.0, Viento.fuerza,
			1000.0 * Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS),
			Engine.get_frames_per_second()]
		for vv in [0, 1]:
			vista = vv
			salida += "\n--- %s ---" % NOMBRES[vv]
			for v in _velas:
				var dd: Dictionary = v.datos_depuracion()
				if dd.is_empty():
					continue
				salida += _pintar(dd)
		print(salida)
		return

	_im.clear_surfaces()
	_im.surface_begin(Mesh.PRIMITIVE_LINES, _mat)
	var txt := "[F3] ON   [F4] vista %d/%d: %s   [F5] ver a traves: %s\n" % [
		vista + 1, NOMBRES.size(), NOMBRES[vista], "si" if ver_a_traves else "no"]
	for v in _velas:
		var d: Dictionary = v.datos_depuracion()
		if d.is_empty():
			continue
		txt += _pintar(d)
	if vista == 3:
		txt += _pintar_obstaculos()
	_im.surface_end()
	_lbl.text = txt


## Encuadra la vela mayor y guarda varias tomas. Desde SOTAVENTO se ve la barriga del paño,
## que es lo que interesa comprobar; de través se ve el perfil y cuánto abomba.
func _capturar() -> void:
	var d: Dictionary = {}
	var d_ban: Dictionary = {}
	for v in _velas:
		var dd: Dictionary = v.datos_depuracion()
		if dd.is_empty():
			continue
		if String(dd["nombre"]) == "vela_mayor":
			d = dd
		elif String(dd["nombre"]) == "bandera":
			d_ban = dd
	if d.is_empty():
		push_warning("depurar_vela: no hay vela_mayor que capturar")
		get_tree().quit()
		return

	var cuerpo: SoftBody3D = d["cuerpo"]
	var nn: int = (d["fijo"] as PackedByteArray).size()
	var cam := Camera3D.new()
	cam.fov = 50.0
	get_tree().current_scene.add_child(cam)

	# Para la foto no vale el viento que toque: se fuerza un TRAVÉS (viento perpendicular al
	# rumbo), que es el rumbo con el que la cangreja llena del todo, y se mantiene fijo mientras
	# el paño se asienta. Con el viento variable de la simulación la vela sale medio flameando.
	var proa := -_barco.global_transform.basis.z.normalized()
	var traves := proa.cross(Vector3.UP).normalized()
	for _i in 150:
		Viento.direccion = traves
		Viento.fuerza = 1.0
		await get_tree().process_frame

	# Offsets en múltiplos del vector a sotavento y su perpendicular. El barco NAVEGA, así que
	# el centro se recalcula cada frame o la toma se queda atrás.
	var tomas := [
		["sotavento", 13.0, 5.0, 1.5],
		["traves", 0.0, 16.0, 2.5],
		["barlovento", -12.0, 7.0, 2.0],
		["alta", 8.0, 9.0, 8.0],
	]
	for t in tomas:
		for _i in 8:
			Viento.direccion = traves      # se sigue forzando: el autoload lo mueve cada frame
			Viento.fuerza = 1.0
			var centro := Vector3.ZERO
			for k in nn:
				centro += cuerpo.get_point_transform(k)
			centro /= float(maxi(nn, 1))
			var sot := traves
			var lado := sot.cross(Vector3.UP).normalized()
			cam.current = true                        # otras cámaras se reclaman cada frame
			cam.global_position = centro + sot * float(t[1]) + lado * float(t[2]) \
				+ Vector3.UP * float(t[3])
			cam.look_at(centro)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var ruta := "user://vela_%s.png" % t[0]
		get_viewport().get_texture().get_image().save_png(ruta)
		print("CAPTURA: %s" % ProjectSettings.globalize_path(ruta))

	# La bandera va en la perilla y es pequeña: necesita su propia toma, de cerca.
	if not d_ban.is_empty():
		var cb: SoftBody3D = d_ban["cuerpo"]
		var nb2: int = (d_ban["fijo"] as PackedByteArray).size()
		for t2 in [["bandera", 4.5, 3.0, 0.6], ["bandera_alta", 2.5, 4.0, 2.2]]:
			for _i in 6:
				Viento.direccion = traves
				Viento.fuerza = 1.0
				var c2 := Vector3.ZERO
				for k in nb2:
					c2 += cb.get_point_transform(k)
				c2 /= float(maxi(nb2, 1))
				var lado2 := traves.cross(Vector3.UP).normalized()
				cam.current = true
				cam.global_position = c2 + traves * float(t2[1]) + lado2 * float(t2[2]) \
					+ Vector3.UP * float(t2[3])
				cam.look_at(c2)
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var r2 := "user://vela_%s.png" % t2[0]
			get_viewport().get_texture().get_image().save_png(r2)
			print("CAPTURA: %s" % ProjectSettings.globalize_path(r2))
	get_tree().quit()


func _pintar(d: Dictionary) -> String:
	var cuerpo: SoftBody3D = d["cuerpo"]
	var fijo: PackedByteArray = d["fijo"]
	var anclas: Array = d["anclas"]
	var aristas: PackedInt32Array = d["aristas"]
	var largo0: PackedFloat32Array = d["largo0"]
	var huesos: PackedInt32Array = d["huesos"]
	var pesos: PackedFloat32Array = d["pesos"]
	var skel: Skeleton3D = d["skel"]
	var n: int = fijo.size()

	# Posiciones simuladas. get_point_transform va en GLOBAL.
	var pos := PackedVector3Array()
	pos.resize(n)
	for k in n:
		pos[k] = cuerpo.get_point_transform(k)

	var n_fijos := 0
	for k in n:
		if fijo[k] == 1:
			n_fijos += 1

	var peor := 0.0
	var suma := 0.0
	var n_pas := 0
	var cortas := 0
	var top: Array = []
	var top_abs: Array = []

	if vista == 0:
		for e in largo0.size():
			var ia: int = aristas[e * 2]
			var ib: int = aristas[e * 2 + 1]
			var l0: float = largo0[e]
			if l0 < 1e-6:
				continue
			var l: float = pos[ia].distance_to(pos[ib])
			var f: float = l / l0 - 1.0
			suma += absf(f)
			n_pas += 1
			if l0 < 0.02:
				cortas += 1
			if f > peor:
				peor = f
			if f > aviso_estiramiento * 0.5:
				top.append([f, ia, ib, l0, l])
			_linea(pos[ia], pos[ib], _color_estiramiento(f / maxf(aviso_estiramiento, 0.001)))
		top.sort_custom(func(x, y): return x[0] > y[0])
		# Las cruces blancas marcan las peores en METROS, no en porcentaje: una arista de 2 mm
		# estirada a 2 cm es un +900 % que no se ve, y no es la que hay que buscar.
		top_abs = top.duplicate()
		top_abs.sort_custom(func(x, y): return (x[4] - x[3]) > (y[4] - y[3]))
		for i in mini(12, top_abs.size()):
			var par: Array = top_abs[i]
			_cruz(pos[par[1]], tam_cruz * 2.0, Color(1, 1, 1))
			_cruz(pos[par[2]], tam_cruz * 2.0, Color(1, 1, 1))
	elif vista == 1:
		for k in n:
			if fijo[k] == 1:
				_cruz(pos[k], tam_cruz, Color(1, 0.15, 0.15))
				var pa: Vector3 = (anclas[k] as Node3D).global_transform.origin
				var dist: float = pos[k].distance_to(pa)
				if dist > 0.005:
					_linea(pos[k], pa, Color(1, 0.1, 1))
					if dist > peor:
						peor = dist
			else:
				_cruz(pos[k], tam_cruz * 0.6, Color(0.15, 1, 0.3))
	elif vista == 2:
		for k in n:
			var mejor := -1
			var mw := 0.0
			for j in 4:
				var w: float = pesos[k * 4 + j]
				if w > mw:
					mw = w
					mejor = huesos[k * 4 + j]
			var nom := "?"
			if mejor >= 0 and mejor < skel.get_bone_count():
				nom = skel.get_bone_name(mejor)
			var c: Color = COLOR_HUESO.get(nom, Color(0.5, 0.5, 0.5))
			_cruz(pos[k], tam_cruz * (1.0 if fijo[k] == 1 else 0.6), c)

	var s := "\n%s: %d vertices, %d fijos, %d libres%s\n" % [
		d["nombre"], n, n_fijos, n - n_fijos, "   RECOGIENDO" if d["recogiendo"] else ""]
	# Lo que el cuerpo tiene DE VERDAD, no lo que dice la escena: los parametros se aplican
	# antes de meterlo en el arbol y conviene comprobar que llegaron.
	s += "   rigidez %.2f  precision %d  masa %.1f  amort %.3f  arrastre %.2f  mascara %d\n" % [
		cuerpo.linear_stiffness, cuerpo.simulation_precision, cuerpo.total_mass,
		cuerpo.damping_coefficient, cuerpo.drag_coefficient, cuerpo.collision_mask]
	# Cuanto se ha ido cada vertice LIBRE de donde le tocaria estar segun la PIEL (no segun el
	# reposo crudo: el trimado y el izado mueven la piel metros, y eso no es hinchado).
	var reposo: PackedVector3Array = d["reposo"]
	var gt := skel.global_transform
	var nb := skel.get_bone_count()
	var mats: Array[Transform3D] = []
	mats.resize(nb)
	for i in nb:
		mats[i] = skel.get_bone_global_pose(i) * skel.get_bone_global_rest(i).affine_inverse()
	var suma_r := 0.0
	var peor_r := 0.0
	var lejos := 0
	var n_libres := 0
	var peor_ident := 0.0
	# Piel de CADA vertice (donde el esqueleto dice que deberia estar) y cuanto se separa esa
	# piel del reposo crudo de la malla, que es lo que el SoftBody tomo como forma inicial.
	var piel_g := PackedVector3Array()
	piel_g.resize(n)
	var desf := PackedFloat32Array()
	desf.resize(n)
	for k in n:
		var piel := Vector3.ZERO
		var tw := 0.0
		for j in 4:
			var w: float = pesos[k * 4 + j]
			if w <= 0.0:
				continue
			var b: int = huesos[k * 4 + j]
			if b < 0 or b >= nb:
				continue
			piel += (mats[b] * reposo[k]) * w
			tw += w
		if tw <= 0.0:
			piel = reposo[k]
		piel = gt * piel
		piel_g[k] = piel
		desf[k] = piel.distance_to(gt * reposo[k])
	var desf_max := 0.0
	var desf_sum := 0.0
	for k in n:
		desf_max = maxf(desf_max, desf[k])
		desf_sum += desf[k]
	for k in n:
		var piel: Vector3 = piel_g[k]
		if fijo[k] == 1:
			# Un fijado DEBE estar en su piel. Si no lo esta, el indice k del cuerpo no es
			# mi vertice k: Godot habria reordenado los puntos y mis aristas unirian pares
			# equivocados, que es lo unico que explica un estiron inmune a los parametros.
			peor_ident = maxf(peor_ident, pos[k].distance_to(piel))
			continue
		var dr: float = pos[k].distance_to(piel)
		suma_r += dr
		n_libres += 1
		peor_r = maxf(peor_r, dr)
		if dr > 0.5:
			lejos += 1
	s += "   hinchado (libres respecto a su piel): media %.3f m  PEOR %.3f m  a mas de 0,5 m: %d\n" % [
		suma_r / maxf(n_libres, 1), peor_r, lejos]
	s += "   comprobacion de indices (fijado vs su piel, deberia ser 0): %.4f m\n" % peor_ident
	# Un vertice que el script cree LIBRE pero que el cuerpo sigue teniendo clavado no lo mueve
	# ningun parametro del solver: se queda donde lo pillo el agarre del arriado.
	var clavados_de_mas := 0
	var sueltos_de_menos := 0
	for k in n:
		var pin: bool = cuerpo.is_point_pinned(k)
		if fijo[k] == 0 and pin:
			clavados_de_mas += 1
		elif fijo[k] == 1 and not pin:
			sueltos_de_menos += 1
	s += "   PINS: libres que siguen clavados: %d   fijos sin clavar: %d\n" % [
		clavados_de_mas, sueltos_de_menos]
	s += "   PIEL vs REPOSO de la malla: media %.3f m  MAXIMO %.3f m\n" % [
		desf_sum / maxf(n, 1), desf_max]
	# Cuanto DEFORMA la piel el pano: distancia entre las pieles de las dos puntas de cada
	# arista, contra su largo de reposo. Un giro rigido da 0 %. Si esto se parece al
	# estiramiento observado, el culpable son los PESOS, no la fisica.
	var sp_sum := 0.0
	var sp_max := 0.0
	var sp_graves := 0
	for e in largo0.size():
		var l0e: float = largo0[e]
		if l0e < 1e-6:
			continue
		var fp: float = piel_g[aristas[e * 2]].distance_to(piel_g[aristas[e * 2 + 1]]) / l0e - 1.0
		sp_sum += absf(fp)
		if fp > sp_max:
			sp_max = fp
		if fp > aviso_estiramiento:
			sp_graves += 1
	s += "   deformacion QUE PIDE LA PIEL: media %.2f %%  MAXIMA %.0f %%  aristas > %.0f %%: %d\n" % [
		100.0 * sp_sum / maxf(largo0.size(), 1), 100.0 * sp_max,
		100.0 * aviso_estiramiento, sp_graves]
	if vista == 0:
		for i in mini(3, top_abs.size()):
			var pp: Array = top_abs[i]
			var k1: int = pp[1]
			var k2: int = pp[2]
			s += "     v%d: piel-reposo %.2f  pos-piel %.2f  |  v%d: piel-reposo %.2f  pos-piel %.2f\n" % [
				k1, desf[k1], pos[k1].distance_to(piel_g[k1]),
				k2, desf[k2], pos[k2].distance_to(piel_g[k2])]
	if vista == 0:
		var graves: int = top.filter(func(x): return x[0] > aviso_estiramiento).size()
		s += "   medio %.2f %%   PEOR %.0f %%   >%.0f %%: %d   aristas de reposo < 2 cm: %d\n" % [
			100.0 * suma / maxf(n_pas, 1), 100.0 * peor, 100.0 * aviso_estiramiento,
			graves, cortas]
		s += "   peores en METROS (las de la cruz blanca):\n"
		for i in mini(4, top_abs.size()):
			var pa2: Array = top_abs[i]
			s += "     v%d-v%d  reposo %.3f -> %.3f m  (+%.3f m, +%.0f %%)  %s/%s\n" % [
				pa2[1], pa2[2], pa2[3], pa2[4], pa2[4] - pa2[3], 100.0 * pa2[0],
				"fijo" if fijo[pa2[1]] == 1 else "libre",
				"fijo" if fijo[pa2[2]] == 1 else "libre"]
		s += "   peores en PORCENTAJE:\n"
		for i in mini(3, top.size()):
			var p2: Array = top[i]
			s += "     v%d-v%d  reposo %.3f -> %.3f m  (+%.3f m, +%.0f %%)  %s/%s\n" % [
				p2[1], p2[2], p2[3], p2[4], p2[4] - p2[3], 100.0 * p2[0],
				"fijo" if fijo[p2[1]] == 1 else "libre",
				"fijo" if fijo[p2[2]] == 1 else "libre"]
	elif vista == 1:
		s += "   maxima distancia de un fijado a su ancla: %.3f m\n" % peor
		s += "   mascara de colision de la vela: %d\n" % cuerpo.collision_mask
	return s


func _pintar_obstaculos() -> String:
	var s := "\nOBSTACULOS\n"
	for n in _barco.find_children("Percha_*", "StaticBody3D", true, false):
		var sb := n as StaticBody3D
		for c in sb.find_children("*", "CollisionShape3D", true, false):
			var cs := c as CollisionShape3D
			var cap := cs.shape as CapsuleShape3D
			if cap == null:
				continue
			var t := cs.global_transform
			var r: float = cap.radius
			var h: float = maxf(cap.height * 0.5 - r, 0.0)
			var col := Color(1, 0.55, 0.1)
			for i in 16:
				var a0 := TAU * i / 16.0
				var a1 := TAU * (i + 1) / 16.0
				for lado in [h, -h]:
					_linea(t * Vector3(cos(a0) * r, lado, sin(a0) * r),
						t * Vector3(cos(a1) * r, lado, sin(a1) * r), col)
				if i % 4 == 0:
					_linea(t * Vector3(cos(a0) * r, h, sin(a0) * r),
						t * Vector3(cos(a0) * r, -h, sin(a0) * r), col)
			s += "   %s  capa %d  r=%.3f  largo=%.2f\n" % [sb.name, sb.collision_layer, r, cap.height]

	var dir: Vector3 = Viento.direccion.normalized()
	var fue: float = Viento.fuerza
	for v in _velas:
		var d: Dictionary = v.datos_depuracion()
		if d.is_empty():
			continue
		var cuerpo: SoftBody3D = d["cuerpo"]
		var nn: int = (d["fijo"] as PackedByteArray).size()
		var c0 := Vector3.ZERO
		for k in nn:
			c0 += cuerpo.get_point_transform(k)
		c0 /= float(maxi(nn, 1))
		var punta := c0 + dir * (1.0 + 4.0 * fue)
		_linea(c0, punta, Color(0.2, 1, 1))
		_cruz(punta, 0.25, Color(0.2, 1, 1))
	s += "   viento: dir (%.2f, %.2f, %.2f)  fuerza %.2f\n" % [dir.x, dir.y, dir.z, fue]
	return s
