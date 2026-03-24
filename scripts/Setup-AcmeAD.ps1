Import-Module ActiveDirectory

# 1. Variables Globales 
$domainName = "acme.local"
$domainPath = "DC=acme,DC=local"
$baseOUName = "Acme_Operaciones"
$baseOUPath = "OU=$baseOUName,$domainPath"

# Contraseña genérica para los usuarios de prueba
$SecurePassword = ConvertTo-SecureString "PasswordTemporal.2026!" -AsPlainText -Force

Write-Host "Iniciando configuración del Directorio Activo para ACME..." -ForegroundColor Cyan

# 2. Creación de la Unidad Organizativa (OU) Principal y Sub-OUs
try {
    if (!(Get-ADOrganizationalUnit -Filter "Name -eq '$baseOUName'")) {
        Write-Host "Creando OU Principal: $baseOUName..."
        New-ADOrganizationalUnit -Name $baseOUName -Path $domainPath -ProtectedFromAccidentalDeletion $false
        
        # Sub-OUs para mantener el orden
        New-ADOrganizationalUnit -Name "Usuarios" -Path $baseOUPath -ProtectedFromAccidentalDeletion $false
        New-ADOrganizationalUnit -Name "Grupos" -Path $baseOUPath -ProtectedFromAccidentalDeletion $false
    } else {
        Write-Host "La OU $baseOUName ya existe. Saltando..." -ForegroundColor Yellow
    }
} catch {
    Write-Error "Error creando las OUs: $_"
}

# Rutas de las nuevas Sub-OUs
$usersOUPath = "OU=Usuarios,$baseOUPath"
$groupsOUPath = "OU=Grupos,$baseOUPath"

# 3. Creación de los Grupos de Seguridad (RBAC)
$grupos = @("Mecanicos_Grupo", "Conductores_Grupo", "RRHH_Grupo", "Partners_Externos")

foreach ($grupo in $grupos) {
    if (!(Get-ADGroup -Filter "Name -eq '$grupo'")) {
        Write-Host "Creando Grupo de Seguridad: $grupo..."
        New-ADGroup -Name $grupo -GroupScope Global -Path $groupsOUPath -Description "Grupo de acceso para $grupo"
    } else {
        Write-Host "El grupo $grupo ya existe. Saltando..." -ForegroundColor Yellow
    }
}

# 4. Creación de Usuarios de Prueba y Asignación de Grupos
$usuarios = @(
    [pscustomobject]@{ Nombre="Juan Perez"; Sam="jperez"; Rol="Mecanico"; Grupo="Mecanicos_Grupo" },
    [pscustomobject]@{ Nombre="Ana Garcia"; Sam="agarcia"; Rol="Conductora"; Grupo="Conductores_Grupo" },
    [pscustomobject]@{ Nombre="Luis Gomez"; Sam="lgomez"; Rol="RRHH"; Grupo="RRHH_Grupo" }
)

foreach ($usr in $usuarios) {
    if (!(Get-ADUser -Filter "SamAccountName -eq '$($usr.Sam)'")) {
        Write-Host "Creando usuario: $($usr.Nombre) ($($usr.Rol))..."
        
        New-ADUser -Name $usr.Nombre `
                   -SamAccountName $usr.Sam `
                   -UserPrincipalName "$($usr.Sam)@$domainName" `
                   -Path $usersOUPath `
                   -AccountPassword $SecurePassword `
                   -Enabled $true `
                   -Description $usr.Rol
                   
        Write-Host "Añadiendo $($usr.Sam) al grupo $($usr.Grupo)..."
        Add-ADGroupMember -Identity $usr.Grupo -Members $usr.Sam
    } else {
        Write-Host "El usuario $($usr.Sam) ya existe. Saltando..." -ForegroundColor Yellow
    }
}

Write-Host "¡Configuración de AD completada con éxito!" -ForegroundColor Green
