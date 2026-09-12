extends Node

## A que velocidad avanzan las crestas, medida siguiendo una, y a que distancia del origen se
## mide.
##
## Dos velocidades se suman en lo que se ve y conviene no confundirlas:
##
## - La de FASE, `omega/k = sqrt(g·L/2pi)`: la que le toca a una ola de esa longitud en agua
##   profunda. Es la misma en todas partes.
## - La que aparece cuando el campo de olas GIRA. Si la direccion de la mar se mueve un angulo,
##   la fase de un punto a distancia D del origen cambia como `k·D·dtheta`, o sea que la cresta
##   se corre a `D·dtheta/dt`. **Crece con la distancia al origen del mundo**, asi que el mar se
##   mueve cada vez mas rapido segun te alejas navegando, y si el giro es de ida y vuelta el mar
##   avanza y retrocede.
##
## Por eso se mide en tres sitios y no en uno: en el origen el segundo efecto vale cero y el mar
## parece correcto.
##
##     godot --path . tools/velocidad_de_las_olas.tscn
##     godot --path . tools/velocidad_de_las_olas.tscn -- 0.0   # sin bamboleo de direccion

const DISTANCIAS := [0.0, 100.0, 300.0]
const SEGUNDOS := 10.0
const VENTANA := 14.0    # cuanto se busca la cresta a cada lado, en metros
const PASO := 0.05


func _ready() -> void:
	get_tree().create_timer(180.0).timeout.connect(func(): get_tree().quit(1))
	await get_tree().create_timer(1.0).timeout
	Viento.direccion_base = Vector3(1, 0, 0)
	Viento.variacion_fuerza = 0.0
	Viento.fuerza_base = 1.0
	for a in OS.get_cmdline_user_args():
		Viento.bamboleo_dir = String(a).to_float()
	await get_tree().process_frame
	await get_tree().process_frame
	Oleaje.asentar()

	print("\n─── velocidad de las olas ───")
	print("bamboleo de direccion del viento: %.3f rad" % Viento.bamboleo_dir)
	print("\nvelocidad de FASE que le toca a cada tren (sqrt(g·L/2pi)):")
	for l in Oleaje.LARGOS:
		var largo := float(l)
		print("   ola de %5.1f m -> %5.2f m/s   (tarda %.1f s en recorrer su propia longitud)"
			% [largo, sqrt(9.81 * largo / TAU), largo / sqrt(9.81 * largo / TAU)])

	var dir := Vector2(1, 0)
	print("\n%-14s %14s %14s %14s" % ["a distancia", "cresta m/s", "minima", "maxima"])
	for d in DISTANCIAS:
		var centro := Vector2(float(d), 0.0)
		var vs: Array[float] = []
		var antes := _cresta(centro, dir)
		var t := 0.0
		while t < SEGUNDOS:
			await get_tree().process_frame
			var dt := get_process_delta_time()
			t += dt
			var ahora := _cresta(centro, dir)
			var v: float = (ahora - antes) / maxf(dt, 0.0001)
			antes = ahora
			# Un salto de una cresta a la siguiente no es velocidad, es el maximo cambiando de
			# sitio: se descarta por imposible (nada del mar va a 40 m/s).
			if absf(v) < 40.0:
				vs.append(v)
		vs.sort()
		if vs.is_empty():
			continue
		print("%-14s %14.2f %14.2f %14.2f"
			% ["%.0f m" % d, vs[vs.size() / 2], vs[int(vs.size() * 0.05)],
				vs[int(vs.size() * 0.95)]])
	get_tree().quit(0)


## Donde esta la cresta mas alta a lo largo de `dir`, en metros desde `centro`.
func _cresta(centro: Vector2, dir: Vector2) -> float:
	var mejor := 0.0
	var mejor_h := -INF
	var n := int(VENTANA / PASO)
	for i in range(-n, n + 1):
		var s := float(i) * PASO
		var h: float = Oleaje.desplazamiento(centro + dir * s).y
		if h > mejor_h:
			mejor_h = h
			mejor = s
	return mejor
