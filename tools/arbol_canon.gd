extends Node

## Cómo queda el árbol del cañón al importarlo, y dónde caen sus ruedas. Existe porque supuse
## la estructura del `.glb` en vez de mirarla: `find_child("canon_curena")` no encuentra la
## cureña si ES la raíz de la escena importada, y las ruedas salían a 1,36 m de su sitio.

func _ready() -> void:
	var esc := load("res://assets/models/canon.glb") as PackedScene
	var m := esc.instantiate() as Node3D
	add_child(m)
	await get_tree().process_frame
	_ver(m, 0)
	get_tree().quit(0)


func _ver(n: Node, prof: int) -> void:
	var t := ""
	if n is Node3D:
		var n3 := n as Node3D
		t = "  pos=%s  basis_x=%s" % [str(n3.position.snappedf(0.001)),
			str(n3.transform.basis.x.snappedf(0.01))]
	print("%s%s [%s]%s" % ["    ".repeat(prof), n.name, n.get_class(), t])
	for h in n.get_children():
		_ver(h, prof + 1)
