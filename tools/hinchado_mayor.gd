extends Node

## Cuánto se INFLA la mayor, y cuánto viento hace falta para que se infle.
##
## El hinchado es lo que cada punto LIBRE se ha ido de donde le tocaría estar según la PIEL —no
## según el reposo crudo, que el trimado y el izado mueven la piel metros y eso no es barriga—.
## Es la misma cuenta que hace `depurar_tela.gd` en su volcado.
##
## Se barre `empuje_viento` porque el 10 de septiembre de 2026, al empujar los anclajes al
## servidor en cada paso, el paño se quedó más plano: el salto por frame de hasta 218 mm que
## tenían las anclas estaba metiendo energía y haciendo de barriga falsa. Hay que reponerla con
## viento de verdad, y medir que no se pague en estiramiento.

const EMPUJES := [7.0, 40.0, 56.0]

var _b: Node3D


func _process(_d: float) -> void:
	if _b != null and is_instance_valid(_b):
		_b.set("anclado", false)


func _ready() -> void:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	_b = esc.instantiate() as Node3D
	add_child(_b)
	Viento.direccion_base = Vector3(1, 0, 0)
	Viento.bamboleo_dir = 0.0
	Viento.variacion_fuerza = 0.0
	await get_tree().create_timer(10.0).timeout

	var telas := {}
	for h in _b.get_children():
		if h.has_method("datos_depuracion") and not h.datos_depuracion().is_empty():
			telas[str(h.get("nombre_malla"))] = h
	print("\nfisica a %d Hz, viento portando (factor %.2f)"
		% [Engine.physics_ticks_per_second, _b.call("factor_viento")])
	print("%-11s %5s %-10s %-10s %7s %9s %10s"
		% ["pano", "emp", "hinchado", "peor", "> 0,5 m", "estira", "> 25 %"])
	for nombre in ["vela_mayor", "foque"]:
		if not telas.has(nombre):
			continue
		var tela: Node = telas[nombre]
		var original: float = tela.get("empuje_viento")
		for e in EMPUJES:
			tela.set("empuje_viento", e)
			await get_tree().create_timer(5.0).timeout
			var r := await _medir(tela)
			print("%-11s %5.0f %8.3f m %8.3f m %7d %9.4f %10d"
				% [nombre, e, r["medio"], r["peor"], r["lejos"], r["estira"], r["malas"]])
		tela.set("empuje_viento", original)
	get_tree().quit()


func _medir(tela: Node) -> Dictionary:
	var d: Dictionary = tela.datos_depuracion()
	var cuerpo: SoftBody3D = d["cuerpo"]
	var skel: Skeleton3D = d["skel"]
	var reposo: PackedVector3Array = d["reposo"]
	var fijo: PackedByteArray = d["fijo"]
	var hueso: PackedInt32Array = d["huesos"]
	var peso: PackedFloat32Array = d["pesos"]
	var ar: PackedInt32Array = d["aristas"]
	var l0s: PackedFloat32Array = d["largo0"]
	var suma := 0.0
	var peor := 0.0
	var lejos := 0
	var n := 0
	var est := 0.0
	var ne := 0
	var malas := 0
	# Cuatro instantes, para no quedarse con un fotograma suelto de un paño que respira.
	for _t in 4:
		for _f in 15:
			await get_tree().physics_frame
		var gt := skel.global_transform
		var nb := skel.get_bone_count()
		var mats: Array[Transform3D] = []
		mats.resize(nb)
		for i in nb:
			mats[i] = skel.get_bone_global_pose(i) * skel.get_bone_global_rest(i).affine_inverse()
		for k in fijo.size():
			if fijo[k] == 1:
				continue
			var piel := Vector3.ZERO
			var w_t := 0.0
			for j in 4:
				var w: float = peso[k * 4 + j]
				var b: int = hueso[k * 4 + j]
				if w <= 0.0 or b < 0 or b >= nb:
					continue
				piel += (mats[b] * reposo[k]) * w
				w_t += w
			if w_t <= 0.0:
				piel = reposo[k]
			var dr := (gt * piel).distance_to(cuerpo.get_point_transform(k))
			suma += dr
			peor = maxf(peor, dr)
			if dr > 0.5:
				lejos += 1
			n += 1
		var m_malas := 0
		for e in l0s.size():
			var l0: float = l0s[e]
			if l0 < 1e-6:
				continue
			var l := cuerpo.get_point_transform(ar[e * 2]).distance_to(cuerpo.get_point_transform(ar[e * 2 + 1]))
			est += absf(l - l0) / l0
			ne += 1
			if (l - l0) / l0 > 0.25:
				m_malas += 1
		malas = maxi(malas, m_malas)
	return {"medio": suma / maxf(n, 1) , "peor": peor, "lejos": int(lejos / 4.0),
		"estira": est / maxf(ne, 1), "malas": malas}
