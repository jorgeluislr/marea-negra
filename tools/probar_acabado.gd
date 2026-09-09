extends Node

## Compara el casco con y sin el acabado de madera: dos capturas y el contraste local medido.
##
## El contraste local (media de |pixel - vecino|) sube si el relieve se ve, y no sube si el
## detalle no se esta aplicando. Sin esta medida es facil creer que funciona mirando una
## captura que en realidad es identica.

const SALIDA := "user://acabado_"

var _modelo: Node3D
var _acabados: Array = []
var _paso := 0
var _fotos := {}


func _ready() -> void:
	var esc := load("res://assets/models/balandra.glb") as PackedScene
	_modelo = esc.instantiate() as Node3D
	add_child(_modelo)
	# camara de tres cuartos sobre el costado, cerca, que es donde se ve la madera
	var cam := Camera3D.new()
	cam.fov = 45.0
	add_child(cam)                      # look_at exige estar YA en el arbol
	cam.position = Vector3(3.2, 2.4, 1.6)
	cam.look_at(Vector3(0.0, 1.4, 0.0))
	cam.make_current()
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-38.0, 35.0, 0.0)
	sol.light_energy = 2.2
	add_child(sol)
	var amb := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.45, 0.52, 0.62)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.62)
	e.ambient_light_energy = 0.7
	amb.environment = e
	add_child(amb)
	var palos := AcabadoMadera.new()
	palos.materiales = PackedStringArray([
		"madera_percha_h", "madera_botalon", "madera_timon", "madera_palos_h_bake"])
	var tablas := AcabadoMadera.new()
	tablas.materiales = PackedStringArray(["mat_horneado_C", "cubierta_tablazon_bake"])
	tablas.girar_fibra = true
	_acabados = [palos, tablas]


func _process(_d: float) -> void:
	_paso += 1
	if _paso == 6:
		_fotos["sin"] = _capturar("sin")
	elif _paso == 8:
		for a in _acabados:
			print("materiales tocados: %s" % a.aplicar(_modelo))
	elif _paso == 14:
		_fotos["con"] = _capturar("con")
		_informe()
		get_tree().quit()


func _capturar(etiqueta: String) -> Dictionary:
	var img := get_viewport().get_texture().get_image()
	var ruta := ProjectSettings.globalize_path("res://") + "../capturas_acabado_%s.png" % etiqueta
	img.save_png(ruta)
	# contraste local: cuanto cambia cada pixel respecto a su vecino
	var w := img.get_width()
	var h := img.get_height()
	var suma := 0.0
	var n := 0
	for y in range(2, h - 2, 2):
		for x in range(2, w - 2, 2):
			var a := img.get_pixel(x, y)
			var b := img.get_pixel(x + 2, y)
			var c := img.get_pixel(x, y + 2)
			suma += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			suma += absf(a.r - c.r) + absf(a.g - c.g) + absf(a.b - c.b)
			n += 6
	return {"ruta": ruta, "contraste": suma / maxf(n, 1), "px": "%dx%d" % [w, h]}


func _informe() -> void:
	print("\ncaptura            contraste local")
	for k in ["sin", "con"]:
		var f: Dictionary = _fotos[k]
		print("  %-6s %s   %.6f   -> %s" % [k, f["px"], f["contraste"], f["ruta"]])
	var a: float = _fotos["sin"]["contraste"]
	var b: float = _fotos["con"]["contraste"]
	print("\n>> el contraste %s un %.1f %%" % ["SUBE" if b > a else "baja", 100.0 * (b - a) / maxf(a, 1e-9)])
	if b <= a * 1.02:
		print(">> OJO: el detalle NO se esta aplicando (el contraste no cambia)")
