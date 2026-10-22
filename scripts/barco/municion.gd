class_name Municion
extends Resource

## Lo que se mete en el ánima: una bala rasa, una palanqueta o un saco de metralla.
##
## Es DATO y no comportamiento —quien vuela es `Bala`, quien dispara es `Canon`—, el mismo reparto
## que `Artilleria` y `Carga`. Cada tipo dice cómo sale (velocidad, cuántos proyectiles y con qué
## abanico), cómo se ve y qué rompe al llegar.
##
## **El daño va POR BALAS, no por energía** (decisión del usuario, 18-10-2026): cada impacto resta
## lo mismo a la zona que toca, se dispare de cerca o de lejos. Las cifras son la fracción de la
## zona que se lleva un impacto: 0,10 = diez balas para dejar el costado destrozado.
##
## **La velocidad de boca decide el alcance, y el capitán de IA lo mide probando la pieza**
## (`Canon.alcance_a`), así que un tipo más lento no necesita que nadie le cuente su alcance: con
## la cuña arriba la rasa llega a ~510 m, y la palanqueta, más pesada para su carga y mala de
## volar, a la mitad, que es lo que tenía en la realidad.

## «rasa», «palanqueta» o «metralla». Es la clave de `Barco.pertrechos` y lo que lee el HUD.
@export var tipo := "rasa"
## m/s en la boca, multiplicando la de la pieza (`Canon.velocidad_bala`).
@export var factor_velocidad := 1.0
## Proyectiles por disparo. La metralla es un saco de balas pequeñas.
@export var proyectiles := 1
## Medio ángulo del cono en que se abren los proyectiles, en grados.
@export var dispersion := 0.0
## Radio de cada proyectil, en metros (lo que se ve).
@export var radio := 0.038
## Fracción de integridad que quita un impacto en una zona del casco.
@export var dano_casco := 0.10
## Fracción que quita en el aparejo (palo, perchas, jarcia, velas).
@export var dano_aparejo := 0.04
## Si un impacto en la flotación abre vía de agua. La palanqueta y la metralla no tienen masa
## para atravesar un costado de roble bajo el agua.
@export var abre_via := true

const TIPOS := ["rasa", "palanqueta", "metralla"]


## El tipo por su nombre. Un solo sitio con las cifras: si cada quien se las escribe, el HUD, la
## pieza y la prueba acaban hablando de tres municiones distintas.
static func de(nombre: String) -> Municion:
	var m := Municion.new()
	m.tipo = nombre
	match nombre:
		"palanqueta":
			# Alcance ∝ v²: la mitad de alcance es v/√2.
			m.factor_velocidad = 0.70
			m.radio = 0.038
			m.dano_casco = 0.03
			m.dano_aparejo = 0.12
			m.abre_via = false
		"metralla":
			m.factor_velocidad = 0.55
			m.proyectiles = 9
			m.dispersion = 2.5
			m.radio = 0.016
			m.dano_casco = 0.0
			m.dano_aparejo = 0.015
			m.abre_via = false
		_:
			m.tipo = "rasa"
	return m


## El que sigue en la rueda de la Q.
static func siguiente(nombre: String) -> String:
	var i := TIPOS.find(nombre)
	return TIPOS[(i + 1) % TIPOS.size()]
