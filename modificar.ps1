# Script dedicado a la manipulación de los archivos de los programas portables.
# El script será capáz de realizar 2 acciones: Comprimir y Reinstalar

# Este script debe ubicarse obligatoriamente en la carpeta raíz del programa.

# Comprimir: Comprime la carpeta raíz del programa en un archivo .zip, y así devolverlo a su estado portable.
# Al mismo tiempo, se eliminará dicha carpeta, generando así una especie de transformación más que crear una copia del mismo.

# Reinstalar: Vuelve a descargar el programa desde los repositorios, borra la carpeta raíz del programa, y descomprime el archivo descargado.
# Esta opción también puede servir para actualizar el programa, aunque hay que tener cuidado con los archivos de configuración que están
# dentro de la carpeta raíz


# Función para saber el nombre de usuario de la sesión actual.
# El resultado se concatenará para la variable $appdata_dir
function Get-Username {
    $username = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    for ($i = 0; $i -le $username.Length; $i++) {
        if ($username[$i] -eq "\") {
            break
        }
    }

    return $username.Substring($i+1)
}

[string] $appdata_dir = "C:\Users\" + (Get-Username) + "\Appdata"  # Directorio destinado a APPDATA. De esta variable derivan las siguientes.
[string] $temp_dir = $appdata_dir + "\Local\Temp"  # Directorio donde se descargarán los archivos temporalmente
[string] $program_dir = $appdata_dir + "\Local\Programs"  # Directorio donde se instalarán los programas portables.
[string] $start_menu_dir = $appdata_dir + "\Roaming\Microsoft\Windows\Start Menu\Programs\"  # Directorio donde se ubican los accesos directos de los programas.


# Variables relacionadas al registro de Windows
[string] $registry_uninstall_key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\"
[string] $registry_program_info = "HKCU:\Software\RepoInstaller\"


# Función que verifica que la opción ingresada es un número entero, y además verifica que sea un número válido
function Get-IntegerOption {
    param (
        [int] $min,
        [int] $max
    )

    do {
        $number = 0
        $input = Read-Host " "

        # Intenta convertir el input a un entero
        $isValid = [int]::TryParse($input, [ref]$number)
        
        # Verifica que sea un entero y que esté dentro del rango
        if ($isValid -and $number -ge $min -and $number -le $max) {
            return $number
        } else {
            Out-Null
        }
    } while ($true)
}


# Función que se encarga de realizar la compresión del programa.
function Compress-Program {
    Write-Host "Comprimiendo Programa..."

    $compress_folder = ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::MyDocuments))
    $root_name = (Get-Item -Path $PSScriptRoot).name.Replace(" ", "")
    $root_name_with_space = (Get-Item -Path $PSScriptRoot).name

    Compress-Archive -Path ($PSScriptRoot+"\*") -DestinationPath ($compress_folder+"\"+$root_name+".zip") -Update

    Write-Host "Compresion Completada!"

    if (Test-Path -Path ($registry_uninstall_key+($root_name.Replace(" ", "")))) {
        Remove-Item -Path ($registry_uninstall_key+($root_name.Replace(" ", ""))) -Force -Recurse
    }

    if (Test-Path -Path ($registry_program_info+($root_name.Replace(" ", "")))) {
        Remove-Item -Path ($registry_program_info+($root_name.Replace(" ", ""))) -Force -Recurse
    }

    # Verifica si el archivo existe en "Menú Inicio". Solo borra el archivo, si se creó una subcarpeta,
    # esta no se borra
    $link_file_exist = Get-ChildItem -Path $start_menu_dir -Filter ($root_name_with_space+".lnk") -Recurse

    if ($link_file_exist) {
        Remove-Item -Path ($link_file_exist.FullName) -Force
    }

    # Crea un archivo temporal el cual se encarga de borrar el directorio del programa. Esto
    # con el proposito de borrar este script del directorio sin generar problemas
    $temp_file = $temp_dir+"\temp.ps1"
    
    New-Item -Path $temp_file -Force

    $temp_content = "Remove-Item -Force -Recurse -Path '$PSScriptRoot'"
    Set-Content -Path $temp_file -Force -Value $temp_content

    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File $temp_file" -WindowStyle Hidden
}

# Función que pregunta al usuario qué desea hacer
function Get-Option {
    Write-Host "Elige una Opcion."
    Write-Host "1. Comprimir Programa"
    Write-Host "2. Reinstalar Programa"

    $op = Get-IntegerOption -min 1 -max 2

    switch ($op) {
        1 { Compress-Program }
        2 { Out-Null }
    }
}

Get-Option