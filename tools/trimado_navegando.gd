extends Node

## El trimado de la mayor NAVEGANDO, banda contra banda, y la trasluchada al cruzar la popa.
##
## Anclado las dos bandas salen iguales a 2 mm (`tools/penol_por_banda.tscn`), pero anclado el
## viento aparente es el real y no se puede ver nada de lo que depende de la marcha. Navegando
## entran tres cosas que sí pueden romper la simetría:
##
##  - el viento APARENTE, que con el barco corriendo en popa se adelanta decenas de grados;
##  - la ESCORA, que inclina el eje del mástil a una banda;
##  - la HISTÉRESIS de `Aparejo.CRUZAR_CRUJIA`, que deja la percha donde estaba mientras el
##    viento no cruce de verdad la crujía. Si el viento bambolea justo en el umbral, la percha
##    se queda a BARLOVENTO, y eso se ve como "a babor no gira igual".
##
## La segunda parte rola el viento despacio a través de la popa, como rola en el juego, y anota
## en qué ángulo trasluchó cada banda. Si los dos números no son espejo, la asimetría es esa.
##
##     godot --path . tools/trimado_navegando.tscn

const RUMBOS := [90.0, 120.0, 150.0, 170.0]
const NAVEGAR := 30.0
## Grados por segundo con que rola el viento en la segunda parte. `Viento` bambolea a 0,08 Hz
## sobre 0,12 rad, o sea ~2,2 °/s de punta: este es el mismo orden.
const ROLA := 2.0

var _b: Node3D
var _skel: Skeleton3D
var _hueso := -1
var _apa: Resource
var _penol := Vector3.ZERO


func _ready() -> void:
	get_tree().create_timer(900.0).timeout.connect(func(): get_tree().quit(1))
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	Viento.fuerza_base = 1.0
	await get_tree().create_timer(7.0).timeout
	Oleaje.asentar()
	_b = get_tree().get_first_node_in_group("barco_activo") as Node3D
	if _b == null:
		print("no hay barco"); get_tree().quit(1); return
	for n in _b.find_children("*", "Skeleton3D", true, false):
		_skel = n as Skeleton3D
		break
	var mayor: Node = null
	for h in _b.get_children():
		if h.has_method("datos_depuracion") and str(h.get("nombre_malla")) == "vela_mayor":
			mayor = h
	_apa = mayor.get("aparejo")
	_hueso = _skel.find_bone(String(_apa.get("trimado_hueso")))
	_buscar_penol()

	print("\n─── trimado navegando ───   tope %.0f°" % float(_apa.get("trimado_angulo_max")))
	print("%-9s %-9s %9s %9s %9s %9s %8s"
		% ["viento", "banda", "percha", "β aparen", "penol Y", "escora", "nudos"])
	var tabla := {}
	for beta in RUMBOS:
		for lado in [1.0, -1.0]:
			var d := await _navegar(beta, lado)
			tabla[[beta, lado]] = d
			print("%-9s %-9s %8.1f° %8.1f° %9.3f %8.2f° %8.1f   %s"
				% ["%.0f°" % beta, "estribor" if lado > 0.0 else "babor",
					d["percha"], d["beta_ap"], d["penol_y"], d["escora"], d["nudos"],
					"a sotavento" if signf(d["percha"]) != d["lado_ap"] else "A BARLOVENTO"])
	print("\n%-9s %14s %14s %12s" % ["viento", "percha a babor", "percha a estrib", "diferencia"])
	var peor := 0.0
	for beta in RUMBOS:
		var a: float = absf(tabla[[beta, 1.0]]["percha"])     # viento por estribor -> percha a babor
		var c: float = absf(tabla[[beta, -1.0]]["percha"])
		peor = maxf(peor, absf(a - c))
		print("%-9s %13.1f° %13.1f° %11.1f°" % ["%.0f°" % beta, a, c, a - c])
	print("PEOR diferencia de ángulo entre bandas navegando: %.1f°" % peor)

	# --- Segunda parte: cruzar la popa despacio, a un lado y al otro.
	print("\n─── trasluchada al cruzar la popa (viento rolando a %.0f °/s) ───" % ROLA)
	await _cruzar(1.0)
	await _cruzar(-1.0)
	get_tree().quit(0)


func _navegar(beta: float, lado: float) -> Dictionary:
	var t := 0.0
	while t < NAVEGAR:
		var desde := Vector3(sin(deg_to_rad(beta)) * lado, 0.0, -cos(deg_to_rad(beta)))
		Viento.direccion_base = (_b.global_transform.basis * -desde).normalized()
		_b.set("anclado", false)
		_b.set("gobierno", true)
		await get_tree().physics_frame
		t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
	return _leer()


## Rola el viento desde `lado` hasta la banda contraria pasando por la popa, y anota dónde cruzó
## la percha. Se mide el ángulo del viento APARENTE, que es el que ve el aparejo.
func _cruzar(lado: float) -> void:
	# Se arranca bien metido en esa banda para que la percha esté asentada.
	var a := 140.0
	var t := 0.0
	while t < 20.0:
		var desde := Vector3(sin(deg_to_rad(a)) * lado, 0.0, -cos(deg_to_rad(a)))
		Viento.direccion_base = (_b.global_transform.basis * -desde).normalized()
		_b.set("anclado", false)
		await get_tree().physics_frame
		t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
	var signo0: float = signf(_leer()["percha"])
	print("  arranca con el viento a %.0f° por %s, percha a %s"
		% [a, "estribor" if lado > 0.0 else "babor", "estribor" if signo0 > 0.0 else "babor"])
	# Ahora el viento rola hacia la otra banda pasando por la popa.
	var recorrido := 0.0
	var cruzo := false
	while recorrido < 80.0:
		var ang := a + recorrido
		var real := ang if ang <= 180.0 else 360.0 - ang
		var l := lado if ang <= 180.0 else -lado
		var desde := Vector3(sin(deg_to_rad(real)) * l, 0.0, -cos(deg_to_rad(real)))
		Viento.direccion_base = (_b.global_transform.basis * -desde).normalized()
		_b.set("anclado", false)
		await get_tree().physics_frame
		recorrido += ROLA / maxf(Engine.physics_ticks_per_second, 1)
		var d := _leer()
		if not cruzo and signf(d["percha"]) != signo0 and absf(d["percha"]) > 5.0:
			cruzo = true
			print("  traslucha con el viento real a %.0f° por %s (aparente %.0f°), percha %.0f°"
				% [real, "estribor" if l > 0.0 else "babor", d["beta_ap"], d["percha"]])
	if not cruzo:
		var d := _leer()
		print("  NO traslucha en 80° de roladura: acaba con la percha a %.0f° (aparente %.0f°)"
			% [d["percha"], d["beta_ap"]])


func _leer() -> Dictionary:
	# El PENOL de la botavara, un punto de su malla llevado a donde esta ahora por la matriz del
	# hueso. Leer un eje de la pose y adivinar cual de los tres barre es fragil: basta que el
	# casco escore para que la eleccion cambie de eje y el angulo salga del perpendicular.
	var m := _skel.get_bone_global_pose(_hueso) * _skel.get_bone_global_rest(_hueso).affine_inverse()
	var p := _b.global_transform.affine_inverse() * (_skel.global_transform * (m * _penol))
	var vel: Vector3 = (_b as CharacterBody3D).velocity
	var ap := _b.global_transform.basis.inverse() * Viento.aparente(vel)
	var apv := Vector2(ap.x, ap.z).normalized()
	return {
		"percha": rad_to_deg(atan2(p.x, p.z)),
		"beta_ap": rad_to_deg(acos(clampf(apv.y, -1.0, 1.0))),
		"lado_ap": signf(apv.x),
		"penol_y": p.y,
		"escora": rad_to_deg(_b.global_transform.basis.get_euler().z),
		"nudos": vel.length() * 1.94384,
	}


## El penol en reposo, en espacio del esqueleto: el vertice de la botavara mas lejano del origen
## de su hueso.
func _buscar_penol() -> void:
	var l := _b.find_children("botavara", "MeshInstance3D", true, false)
	if l.is_empty():
		return
	var mi := l[0] as MeshInstance3D
	var tr := Transform3D()
	var x: Node = mi
	while x != null and x != _skel:
		if x is Node3D: tr = (x as Node3D).transform * tr
		x = x.get_parent()
	var o := _skel.get_bone_global_rest(_hueso).origin
	var d := -1.0
	for v in (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		var q := tr * v
		if (q - o).length() > d:
			d = (q - o).length(); _penol = q
