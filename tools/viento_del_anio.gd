extends Control
## El viento de un año del calendario, mes a mes: de dónde viene (media, mínimo y máximo de cada
## mes, muestreando cada hora) y con qué fuerza.
##
##     godot --path . tools/viento_del_anio.tscn              # 1716
##     godot --path . tools/viento_del_anio.tscn -- 1720
##
## Imprime la tabla y la dibuja: la franja es el rango del mes, la línea la media y los puntos el
## rumbo de cada mediodía. La fuerza sale constante a propósito: el clima solo gobierna la
## DIRECCIÓN (ver `ClimaCaribe`). `VIENTO_ANIO_FOTO=<png>` guarda la vista y sale.

const MESES := ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]
## Rango vertical del dibujo, en grados (de dónde viene).
const ARRIBA := 0.0
const ABAJO := 180.0

var _anio := 1716
var _media := PackedFloat32Array()
var _min := PackedFloat32Array()
var _max := PackedFloat32Array()
var _mediodias := PackedVector2Array()   # x = día del año, y = rumbo


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_int():
		_anio = args[0].to_int()
	_barrer()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	queue_redraw()
	var foto := OS.get_environment("VIENTO_ANIO_FOTO")
	if foto != "":
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(foto)
		get_tree().quit()


func _barrer() -> void:
	var v_ms := Viento.fuerza_base * Viento.velocidad_m_s
	print("═══ Viento de %d (rumbo = de dónde viene, grados) ═══" % _anio)
	print("mes   media   mín    máx   desv   NE%   E%   SE%  oeste%   fuerza")
	var a0 := Calendario.dia_juliano(_anio, 1, 1)
	for mes in range(1, 13):
		var a := Calendario.dia_juliano(_anio, mes, 1)
		var b := Calendario.dia_juliano(_anio + (1 if mes == 12 else 0), mes % 12 + 1, 1)
		var s := Vector2.ZERO
		var lo := 999.0
		var hi := -999.0
		var cuenta := {"ne": 0, "e": 0, "se": 0, "o": 0}
		var vals := []
		var t := float(a)
		while t < b:
			var r := fposmod(ClimaCaribe.rumbo(t), 360.0)
			vals.append(r)
			s += Vector2(sin(deg_to_rad(r)), cos(deg_to_rad(r)))
			lo = minf(lo, r)
			hi = maxf(hi, r)
			if r > 180.0:
				cuenta["o"] += 1
			elif r < 67.5:
				cuenta["ne"] += 1
			elif r < 112.5:
				cuenta["e"] += 1
			else:
				cuenta["se"] += 1
			t += 1.0 / 24.0
		var med := fposmod(rad_to_deg(atan2(s.x, s.y)), 360.0)
		var d2 := 0.0
		for r in vals:
			d2 += pow(wrapf(r - med, -180.0, 180.0), 2.0)
		var n := float(vals.size())
		_media.append(med)
		_min.append(lo)
		_max.append(hi)
		print("%s  %6.1f %6.1f %6.1f %6.1f  %4.0f %4.0f %4.0f  %5.1f   %.2f (%.1f m/s)" % [
			MESES[mes - 1], med, lo, hi, sqrt(d2 / n),
			100.0 * cuenta["ne"] / n, 100.0 * cuenta["e"] / n, 100.0 * cuenta["se"] / n,
			100.0 * cuenta["o"] / n, Viento.fuerza_base, v_ms])
	var fin := Calendario.dia_juliano(_anio + 1, 1, 1)
	for j in range(a0, fin):
		_mediodias.append(Vector2(j - a0, ClimaCaribe.rumbo(j + 0.5)))


func _draw() -> void:
	var r := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, r), Color(0.08, 0.1, 0.13))
	var izq := 70.0
	var der := r.x - 30.0
	var arr := 60.0
	var aba := r.y - 50.0
	var fuente := ThemeDB.fallback_font
	var y_de := func(g: float) -> float: return arr + (g - ARRIBA) / (ABAJO - ARRIBA) * (aba - arr)
	# Rejilla por rumbos: N, NE, E, SE, S.
	for g in [0.0, 45.0, 90.0, 135.0, 180.0]:
		var y: float = y_de.call(g)
		draw_line(Vector2(izq, y), Vector2(der, y), Color(1, 1, 1, 0.15))
		draw_string(fuente, Vector2(8, y + 5), "%s %d°" % [["N", "NE", "E", "SE", "S"][int(g / 45.0)], g],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))
	var ancho_mes := (der - izq) / 12.0
	var linea := PackedVector2Array()
	for i in 12:
		var x0 := izq + i * ancho_mes
		var cx := x0 + ancho_mes * 0.5
		var y0: float = y_de.call(_min[i])
		var y1: float = y_de.call(_max[i])
		draw_rect(Rect2(x0 + 6, y0, ancho_mes - 12, y1 - y0), Color(0.3, 0.6, 0.9, 0.25))
		linea.append(Vector2(cx, y_de.call(_media[i])))
		draw_string(fuente, Vector2(cx - 12, aba + 22), MESES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color(1, 1, 1, 0.8))
		draw_string(fuente, Vector2(cx - 16, y_de.call(_media[i]) - 8), "%.0f°" % _media[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.85, 0.4))
	var dias := float(_mediodias.size())
	for p in _mediodias:
		draw_circle(Vector2(izq + p.x / dias * (der - izq), y_de.call(fposmod(p.y, 360.0))), 2.0,
			Color(0.8, 0.9, 1.0, 0.6))
	draw_polyline(linea, Color(1, 0.85, 0.4), 3.0)
	draw_string(fuente, Vector2(izq, 34),
		"Viento de %d en las Islas Vírgenes: de dónde viene (media, rango del mes y cada mediodía). Fuerza %.2f constante." % [
			_anio, Viento.fuerza_base], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1))
