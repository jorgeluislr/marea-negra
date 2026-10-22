class_name EstiloHud
extends RefCounted

## Colores, letra y umbrales del HUD, en un solo sitio. Estilo de carta grabada de hacia 1700:
## tinta sepia sobre pergamino, con latón en los marcos.
##
## Mientras no lleguen los iconos de Meshy (`fuentes/prompts_meshy.md`, "Iconos del HUD") todo se
## dibuja con estos colores; al llegar, cada pieza toma su textura y estos siguen valiendo para
## tintar el aro de estado.

const PERGAMINO := Color(0.914, 0.851, 0.69)
const PERGAMINO_OSCURO := Color(0.796, 0.725, 0.561)
const TINTA := Color(0.231, 0.141, 0.071)
const TINTA_SUAVE := Color(0.42, 0.29, 0.149)
const LATON := Color(0.659, 0.482, 0.196)
const ROJO_CARTA := Color(0.549, 0.11, 0.075)
const AZUL_VIENTO := Color(0.173, 0.373, 0.525)
const HIERRO := Color(0.165, 0.165, 0.165)

## Estado de las zonas y de los iconos. Verde bien, amarillo algo tocado, rojo crítico.
const VERDE := Color(0.247, 0.549, 0.227)
const AMARILLO := Color(0.85, 0.66, 0.13)
const ROJO := Color(0.72, 0.13, 0.09)
const APAGADO := Color(0.42, 0.353, 0.251)

## Por debajo de esto una zona pasa de verde a amarillo, y de amarillo a rojo.
const UMBRAL_TOCADO := 0.7
const UMBRAL_CRITICO := 0.3

const NUDOS_POR_M_S := 1.943844

static var _letra: Font


static func letra() -> Font:
	if _letra == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Georgia", "Book Antiqua", "Times New Roman", "serif"])
		_letra = f
	return _letra


static func color_integridad(v: float) -> Color:
	if v < UMBRAL_CRITICO:
		return ROJO
	if v < UMBRAL_TOCADO:
		return AMARILLO
	return VERDE


## Rumbo de carta de un nodo: 0 al norte (−Z), 90 al este (+X), en sentido horario. El mismo
## criterio que la carta náutica y `Archipielago`.
static func rumbo_de(n: Node3D) -> float:
	var p := -n.global_transform.basis.z
	return fposmod(rad_to_deg(atan2(p.x, -p.z)), 360.0)


## De dónde VIENE el viento, en grados de carta. `Viento.direccion` es hacia dónde sopla, que es
## lo que necesitan las telas; un marino nombra el viento por donde entra.
static func viento_desde(direccion: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(-direccion.x, direccion.z)), 360.0)


const _CUARTAS := ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
	"S", "SSO", "SO", "OSO", "O", "ONO", "NO", "NNO"]


static func cuarta(grados: float) -> String:
	return _CUARTAS[int(fposmod(grados + 11.25, 360.0) / 22.5) % 16]


## Contorno de la flotación del barco en sus ejes, (x, z): x a estribor, z a popa. Si el casco
## no se pudo medir, una elipse de su `recorte_radio` para que el dibujo no se quede vacío.
static func contorno(b: Node) -> PackedVector2Array:
	var s: Dictionary = b.call("silueta_de_flotacion") if b.has_method("silueta_de_flotacion") else {}
	var pts := PackedVector2Array()
	if s.is_empty():
		var r: Vector2 = b.get("recorte_radio") if "recorte_radio" in b else Vector2(1, 3)
		for i in 32:
			var a := TAU * float(i) / 32.0
			pts.append(Vector2(cos(a) * r.x, sin(a) * r.y))
		return pts
	var lo: float = s["lo"]
	var hi: float = s["hi"]
	var ancho: PackedFloat32Array = s["ancho"]
	var n := ancho.size()
	# Estribor de proa a popa, y babor de vuelta: un polígono cerrado sin cruces.
	pts.append(Vector2(0.0, lo))
	for k in n:
		pts.append(Vector2(ancho[k], lerpf(lo, hi, float(k) / float(maxi(n - 1, 1)))))
	pts.append(Vector2(0.0, hi))
	for k in range(n - 1, -1, -1):
		pts.append(Vector2(-ancho[k], lerpf(lo, hi, float(k) / float(maxi(n - 1, 1)))))
	return pts
