# Marea Negra

Juego 3D de piratas (Godot 4.7) con navegación de barco y exploración/combate a pie, estilo Pirates of the Caribbean.

## Estructura del proyecto

```
marea_negra/
├── project.godot
├── scenes/
│   ├── world/        # Escenas de nivel/mundo (mar, main_world.tscn)
│   ├── barcos/       # barco_base.tscn y una escena por embarcación
│   ├── character/    # Jugador y NPCs
│   └── ui/           # HUD, menús
├── scripts/          # UN PAQUETE POR RESPONSABILIDAD; nada suelto en la raíz
│   ├── barco/        # Barco, Balandra, audio, tapa de agua
│   ├── tela/         # TelaFisica/VelaFisica/BanderaFisica, TelaShader/VelaShader, Aparejo
│   ├── camara/       # Cámaras orbital y de navegación
│   ├── jugador/      # Jugador
│   └── mundo/        # Viento, mar, gestor de barcos, HUD, música, ajustes
├── tests/            # Pruebas del juego (ver más abajo)
├── tools/            # Herramientas de medida y diagnóstico, de usar y tirar
├── assets/
│   ├── models/       # Modelos exportados desde Blender (.glb)
│   ├── textures/     # Texturas
│   └── audio/        # Música y efectos de sonido
├── blender_src/      # Scripts de pipeline y marcado de partes
└── fuentes/          # Todo lo anterior al juego: .blend, crudos de Meshy, prompts
```

Los scripts se cuelgan de las escenas (no van junto al `.tscn`), y **la funcionalidad propia de
un objeto vive en ese objeto**: el timón, los colisionadores de cubierta y el cambio barco ↔ a
pie son métodos de `Barco`; izar, arriar y trimar son métodos de la vela. No hay scripts-nodo
sueltos orquestando a otros por `get_parent()`.

## Estado actual

Ya no es un placeholder de primitivas: los cuatro cascos son modelos reales.

- **Flota de cuatro embarcaciones** (balandra, lancha, barca y goleta), intercambiables en
  marcha con **TAB**. La balandra es la desarrollada: cangreja con pico, foque y bandera.
- **Navegación a vela**: el viento varía en dirección y fuerza, y la propulsión sale del ángulo
  entre la proa y el viento por la superficie de vela abierta. **A/D** al timón, **W** y **S**
  abren y cierran la vela de proa y la de popa, **ESPACIO** el ancla.
- **Velas de tela con física** (`SoftBody3D`): el paño cuelga y se llena de viento, se recoge
  contra la percha al arriar, y la bandera rola a sotavento como una veleta.
- **Se anda por cubierta**: **F** alterna entre el timón y el personaje, que aparece como hijo
  del barco y por eso lo acompaña mientras navega.
- **Visor de tela** para diagnosticar la física: **F3** lo enciende, **F4** cambia de vista,
  **F5** la hace atravesar la geometría.

## Pruebas

```
godot --path . tests/pruebas.tscn
```

Devuelve 1 si algo falla e imprime una línea por comprobación. Hay un fichero por paquete
(`tests/barco_test.gd`, `tela_test.gd`, `mundo_test.gd`), y las pruebas manejan el juego con sus
propias teclas en vez de llamar a los métodos por dentro.

Corren **con ventana y como escena**, y no es opcional: `--headless` no simula `SoftBody3D` (los
puntos se quedan congelados y toda la tela mide "perfecta") y con `-s` no existen los autoloads,
así que nada que use `Viento` llega a compilar. Si acabas de añadir un script con `class_name`,
pasa antes `godot --path . --headless --import`.

## Flujo de trabajo Blender → Godot

1. Modela y anima en Blender, trabajando en **metros reales** (1 unidad Blender = 1 metro).
   Los barcos y personajes de Pirates of the Caribbean son grandes: mide referencias reales
   (un galeón mediano ronda 30-40m de eslora) para que la escala se sienta bien en Godot.
2. Antes de exportar: aplica todas las transformaciones (`Ctrl+A` → Rotation & Scale) y
   asegúrate de que las normales estén correctas.
3. Exporta con **glTF 2.0** (`File > Export > glTF 2.0`), formato `.glb` (binario, todo en un
   archivo) para assets simples, o `glTF Separate` si quieres texturas editables aparte.
   - Godot usa Y-up; el exportador de Blender ya hace esa conversión automáticamente.
   - Activa "+Y Up" (viene por defecto) y exporta solo lo necesario (deselecciona cámaras/luces
     de Blender si no las necesitas en el juego).
4. Guarda el `.glb` exportado directamente dentro de `assets/models/` (usa subcarpetas si el
   proyecto crece, ej. `assets/models/ships/`, `assets/models/characters/`).
5. Godot importa el `.glb` automáticamente. Arrástralo a una escena o instáncialo como
   `PackedScene` para reemplazar los meshes primitivos actuales.
6. Guarda el archivo fuente `.blend` en `blender_src/` (no se usa en el juego directamente,
   pero lo necesitas para futuras ediciones). Estos archivos pueden pesar mucho — considera
   usar Git LFS si el repo crece.

## Próximos pasos sugeridos

- Reemplazar la cápsula del jugador por un modelo con animaciones (idle, correr, trepar,
  espada) usando un `AnimationTree`.
- Mar de verdad: hoy el plano de agua tiene 4 vértices y el oleaje del shader no se ve, y el
  barco se balancea con un `sin()` propio que no tiene relación con el agua. El plan es olas de
  Gerstner con la misma función en el shader y en GDScript, para que el barco flote sobre las
  olas que se ven (y cabecee y escore, no solo suba y baje).
- Combate: espada cuerpo a cuerpo a pie, cañones en el barco (raycast o proyectiles físicos),
  daño al casco y al velamen.
- Combate: espada cuerpo a cuerpo a pie, cañones en el barco (raycast o proyectiles físicos),
  daño al casco y al velamen.
- Mundo: varias islas, sistema de viaje en el mar abierto, puertos donde comprar/vender y
  aceptar misiones.
- Input Map: mover los controles hardcodeados (`Input.is_key_pressed`) al Input Map del
  proyecto para permitir remapeo de teclas desde un menú de opciones.
