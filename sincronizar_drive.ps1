<#
    Sincroniza "Marea Negra" con una carpeta de Google Drive para escritorio.

    Sube el proyecto Godot, las fuentes de Blender y la biblioteca de piezas.
    Deja FUERA todo lo que es respaldo de recuperacion ante fallo (11,2 GB de
    instantaneas de sesion, 6,3 GB de ficheros recuperados de un .blend
    truncado y 1 GB de .blend1 automaticos de Blender), la cache de Godot y la
    carpeta licencias/, que lleva datos personales y no debe viajar a una
    carpeta compartida.

    Por defecto SIMULA: no escribe nada y solo dice que copiaria. Anade
    -Ejecutar para copiar de verdad.

        .\sincronizar_drive.ps1              # simula
        .\sincronizar_drive.ps1 -Ejecutar    # copia de verdad

    El destino por defecto es G:\My Drive\marea_negra, la carpeta que Google
    Drive para escritorio monta en streaming. Si la unidad cambia de letra,
    pasala con -Destino.

    -Espejo (con -Ejecutar) borra en Drive lo que ya no exista en local. Sin
    el, la copia solo anade y actualiza: mas seguro, pero los ficheros que
    renombres se acumulan en el destino.
#>
[CmdletBinding()]
param(
    [string] $Destino = 'G:\My Drive\marea_negra',

    [string] $Origen = 'E:\Godot\Game3D\marea_negra',

    [switch] $Ejecutar,

    [switch] $Espejo
)

$ErrorActionPreference = 'Stop'

# Carpetas excluidas, a cualquier profundidad. "respaldos" cubre de una vez
# fuentes\blend\respaldos y fuentes\blend\biblioteca\respaldos.
$carpetasFuera = @(
    'respaldos',    # instantaneas de sesion: 11,2 GB
    '.git',         # Drive corrompe repositorios git al sincronizar a medias
    '.godot',       # cache regenerable del editor
    '.import',
    '__pycache__',
    'licencias'     # datos personales: nunca a una carpeta compartida
)

# Ficheros excluidos por patron o por nombre.
$ficherosFuera = @(
    '*.blend1', '*.blend2', '*.blend3',   # respaldos automaticos de Blender
    '*.bak',                              # 3,2 GB en dos ficheros
    '*.pyc',
    'balandra_piezas_recuperado.blend',   # 1,8 GB rescatados de un .blend truncado
    'balandra_piezas_rec2.blend',         # 1,3 GB, segundo intento del mismo rescate
    '*_pre_marcado*', '*_pre_etiqueta*',  # modelos anteriores a marcar las partes
    '*_respaldo*', '*_viejo*',
    'desktop.ini', 'Thumbs.db'
)

if (-not (Test-Path -LiteralPath $Origen)) {
    throw "No existe el origen: $Origen"
}

# Si la unidad de Drive no esta montada, robocopy la crearia como carpeta local
# y la copia acabaria en el disco en vez de en la nube, en silencio.
$raiz = [System.IO.Path]::GetPathRoot($Destino)
if (-not (Test-Path -LiteralPath $raiz)) {
    throw "No esta montada la unidad $raiz. Arranca Google Drive para escritorio."
}
if (-not (Test-Path -LiteralPath $Destino)) {
    throw "No existe la carpeta de destino: $Destino. Creala en Drive antes de sincronizar."
}

$opciones = @(
    '/E',           # subcarpetas, incluidas las vacias
    '/FFT',         # marcas de tiempo con 2 s de tolerancia: Drive no da mas
    '/DST',         # ajusta el horario de verano
    '/R:2', '/W:5', # 2 reintentos, 5 s de espera
    '/NP',          # sin porcentaje por fichero
    '/TEE'
)

if ($Espejo) {
    if (-not $Ejecutar) {
        Write-Host 'Aviso: -Espejo solo actua con -Ejecutar.' -ForegroundColor Yellow
    }
    $opciones += '/MIR'
}

if (-not $Ejecutar) {
    $opciones += '/L'   # solo lista; no toca el disco
    Write-Host ''
    Write-Host 'MODO SIMULACION: no se copia nada. Anade -Ejecutar para copiar.' -ForegroundColor Cyan
}

$argumentos = @($Origen, $Destino) + $opciones
$argumentos += $carpetasFuera | ForEach-Object { '/XD'; $_ }
$argumentos += $ficherosFuera | ForEach-Object { '/XF'; $_ }

Write-Host ''
Write-Host "Origen:  $Origen"
Write-Host "Destino: $Destino"
Write-Host ''

$registro = Join-Path $env:TEMP ('marea_negra_drive_{0:yyyyMMdd_HHmmss}.log' -f (Get-Date))
& robocopy.exe @argumentos "/LOG+:$registro"
$codigo = $LASTEXITCODE

Write-Host ''
Write-Host "Registro: $registro"

# Robocopy devuelve un mapa de bits: 0-7 es exito (0 = nada que hacer,
# 1 = copiados, 2 = extras en destino, 4 = desajustes). 8 o mas es fallo real.
if ($codigo -ge 8) {
    Write-Host "robocopy termino con codigo ${codigo}: hubo errores, revisa el registro." -ForegroundColor Red
    exit 1
}

Write-Host "robocopy termino con codigo $codigo (correcto)." -ForegroundColor Green
exit 0
