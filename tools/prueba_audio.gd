extends SceneTree
func _init() -> void:
	for f in ["driza", "viento_calma", "viento_fuerte", "mar", "flameo_vela",
			"flameo_golpe_1", "agua_casco"]:
		var r := "res://assets/audio/%s.wav" % f
		var s := load(r)
		if s == null:
			print("%-16s NO CARGA" % f); continue
		var w := s as AudioStreamWAV
		if w == null:
			print("%-16s carga como %s" % [f, s.get_class()]); continue
		print("%-16s %s  %d Hz  %s  %.2f s  bucle=%s" % [f, w.get_class(), w.mix_rate,
			"estereo" if w.stereo else "mono", w.get_length(),
			AudioStreamWAV.LOOP_DISABLED != w.loop_mode])
	quit()
