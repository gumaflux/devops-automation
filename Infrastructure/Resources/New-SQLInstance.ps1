<#

.SYNOPSIS
Create an Azure SQL Server and datbase

.DESCRIPTION
Create an Azure SQL Server and datbase

.PARAMETER Location
The location of the Resource Group. This is limited to West Europe and North Europe

.PARAMETER ResourceGroupName
The name of the destination Resource Group for the resource

.PARAMETER ServerName
The name of the Azure SQL Server

.PARAMETER ServerAdminUsername
The username of the SA account for the SQL Server

.PARAMETER DatabaseName
One or more database names to create on the given server

.PARAMETER DatbaseEdition
Specifies the edition to assign to the database. The acceptable values for this parameter are:

- Default
- None
- Premium
- Basic
- Standard
- DataWarehouse
- Free

.PARAMETER DatabaseServiceObjective
Specifies the name of the service objective to assign to the database. The default is S0

.EXAMPLE

.EXAMPLE

#>

Param (
    [Parameter(Mandatory = $false)]
	[ValidateSet("West Europe", "North Europe")]
    [String]$Location = $ENV:Location,
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
	[String]$ResourceGroupName = $ENV:ResourceGroup,
    [Parameter(Mandatory = $false)]
    [String]$KeyVaultName,
    [Parameter(Mandatory = $true)]
    [String]$KeyVaultSecretName,
    [Parameter(Mandatory = $true)]    
    [String]$ServerName,
    [Parameter(Mandatory = $true)]
    [String]$ServerAdminUsername,    
    [Parameter(Mandatory = $true)]
    [String[]]$DatabaseName,
    [Parameter(Mandatory = $false)]
    [ValidateSet("Default","None","Premium","Basic","Standard","DataWarehouse","Free")]
    [String]$DatabaseEdition = "Standard",
    [Parameter(Mandatory = $false)]
    [String]$DatabaseServiceObjective = "S0"  
)

# --- Import helper modules
Import-Module (Resolve-Path -Path $PSScriptRoot\..\Modules\Azure.psm1).Path
Import-Module (Resolve-Path -Path $PSScriptRoot\..\Modules\Helpers.psm1).Path

# --- Check for an existing sql server in the subscription
Write-Verbose -Message "Checking for exiting SQL Server $ServerName"
$SQLServer = Find-AzureRmResource -ResourceNameEquals $ServerName

# --- Check for an existing key vault
Write-Verbose -Message "Checking for existing entry for $KeyVaultSecretName in Key Vault $KetVaultName"
$ServerAdminPassword = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -Name $KeyVaultSecretName).SecretValue

if (!$SQLServer){
    Write-Verbose -Message "Attempting to resolve SQL Server name $ServerName globally"
    if ($GloballyResolvable) {
        throw "The SQL Server name $ServerName is globally resolvable. It's possible that this name has already been taken."
    }

    try {

        # --- If a secret doesn't exist create a new password and save it to the vault
        if (!$ServerAdminPassword) {
            Write-Verbose -Message "Creating new entry for $KeyVaultSecretName in Key Vault $KetVaultName"
            $ServerAdminPassword = (New-Password).PasswordAsSecureString
            $null = Set-AzureKeyVaultSecret -VaultName $KeyVaultName -Name $KeyVaultSecretName -SecretValue $ServerAdminPassword
        }

        # --- Set up SQL Server parameters and create a new instance
        Write-Verbose -Message "Attempting to create SQL Server $ServerName"
        $ServerAdminCredentials = [PSCredential]::new($ServerAdminUsername,$ServerAdminPassword)

        $ServerParameters = @{
            Location = $Location
            ResourceGroupName = $ResourceGroupName
            ServerName = $ServerName
            SqlAdministratorCredentials = $ServerAdminCredentials
            ServerVersion = "12.0"
        }

        $Server = New-AzureRmSqlServer @ServerParameters
    } catch {
        throw "Could not create SQL Server $($ServerName): $_"
    }

}

# --- Create or update firewall rules on the SQL Server instance
if ($SQLServer) {
    Write-Verbose -Message "Creating firewall rules"
    Set-SqlServerFirewallRule -FirewallRuleName "AllowAllWindowsAzureIps" -StartIpAddress "0.0.0.0" -EndIpAddress "0.0.0.0" -ServerName $ServerName -ResourceGroupName $ResourceGroupName
    Set-SqlServerFirewallRule -FirewallRuleName "SFA WAN" -StartIpAddress "193.240.137.228" -EndIpAddress "193.240.137.228" -ServerName $ServerName -ResourceGroupName $ResourceGroupName
    Set-SqlServerFirewallRule -FirewallRuleName "SFA Purple" -StartIpAddress "62.253.71.89" -EndIpAddress "62.253.71.89" -ServerName $ServerName -ResourceGroupName $ResourceGroupName
}

# --- If the SQL Server exists in the subscription create databasses
if ($Server -and !$GloballyResolvable) {
    foreach ($Database in $DatabaseName) {
        Write-Verbose -Message "Checking for Database $DatabaseName on SQL Server $ServerName"
        $SQLDatabase = Get-AzureRmSqlDatabase -DatabaseName $Database -ServerName $ServerName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

        # --- If the database doesn't exist, create one
        if (!$SQLDatabase) {
            Write-Verbose -Message "Attempting to create Database $DatabaseName"
            try {
                $SQLDatabaseParameters = @{
                    ResourceGroupName = $ResourceGroupName
                    ServerName = $ServerName
                    DatabaseName = $Database
                    Edition = $DatabaseEdition
                    RequestedServiceObjectiveName = $DatabaseServiceObjective
                }

                $null = New-AzureRmSqlDatabase @SQLDatabaseParameters
            } catch {
                throw "Could not create database $($Database): $_"
            }
        }

        # --- Configure additional settings on the database
    }
}

