class_name Jugador
extends CharacterBody3D

## Controlador básico de personaje a pie.
## Movimiento con WASD, cámara con el mouse, correr con Shift, saltar con
## Espacio, interactuar (ej. subir a un barco) con E.

const WALK_SPEED := 4.0
const RUN_SPEED := 7.5
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.003
const GRAVITY := 9.8

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var interact_ray: RayCast3D = $CameraPivot/Camera3D/InteractRay

var camera_pitch := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_pitch = clamp(camera_pitch - event.relative.y * MOUSE_SENSITIVITY, -1.2, 1.2)
		camera_pivot.rotation.x = camera_pitch

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_E:
			_try_interact()

	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	).normalized()

	# GLOBAL basis, no local: el jugador es hijo del barco, así que transform.basis es relativa
	# al barco. move_and_slide usa la velocidad en espacio global, de modo que con la basis local
	# la W apuntaba mal en cuanto el barco giraba. Con la global, la W siempre va hacia donde
	# mira el personaje de verdad, gire el barco lo que gire.
	var direction := (global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := RUN_SPEED if Input.is_key_pressed(KEY_SHIFT) else WALK_SPEED

	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()


func _try_interact() -> void:
	if interact_ray.is_colliding():
		var target := interact_ray.get_collider()
		if target and target.has_method("on_interact"):
			target.on_interact(self)
