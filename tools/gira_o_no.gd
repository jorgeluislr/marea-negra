extends Node

## ¿Gira el casco cuando se le da la orden de timón? UN solo barco, la orden puesta a mano sin
## capitán ni teclado de por medio, y el rumbo impreso cada medio segundo.
##
## Existe porque `tools/duelo.tscn` dejó el timón a tope (`orden_timon` = ±1) y el rumbo clavado
## en ±90°, y con dos barcos, dos capitanes y una máquina de estados de por medio no se puede
## saber de quién es la culpa. Aquí no hay nada más que el casco y una orden.
##
##     godot --path . --headless tools/gira_o_no.tscn

const ESPERA := 4.0
const DURACION := 8.0
const ORDEN := 1.0
## La configuracion EXACTA del duelo: viento hacia +X y proa a +90 grados (o sea al -X, de
## proa al viento). Es donde el rumbo se quedaba congelado con el timon a tope.
const RUMBO_INICIAL := 90.0
const VIENTO := Vector3(1, 0, 0)


func _ready() -> void:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	var b := esc.instantiate() as Node3D
	add_child(b)
	await get_tree().create_timer(ESPERA).timeout

	b.rotation.y = deg_to_rad(RUMBO_INICIAL)
	Viento.direccion_base = VIENTO
	Viento.bamboleo_dir = 0.0
	Viento.variacion_fuerza = 0.0
	Viento.fuerza_base = 1.0
	b.set("anclado", false)

	print("═══ ¿Gira el casco con la orden de timón? ═══")
	print("orden_timon = %+.2f, viento en popa, %.0f s" % [ORDEN, DURACION])
	print(" %5s %8s %8s %8s %6s %6s" % ["t", "rumbo", "vel", "orden", "vdel", "vtra"])

	var t := 0.0
	var siguiente := 0.0
	while t < DURACION:
		b.set("orden_timon", ORDEN)
		if t >= siguiente:
			siguiente += 0.5
			print(" %5.1f %8.2f %8.2f %8.2f %6s %6s" % [t, rad_to_deg(b.rotation.y),
				float(b.get("velocidad")), float(b.get("orden_timon")),
				str(b.get("vela_delantera")), str(b.get("vela_trasera"))])
		t += get_process_delta_time()
		await get_tree().process_frame
	get_tree().quit(0)
