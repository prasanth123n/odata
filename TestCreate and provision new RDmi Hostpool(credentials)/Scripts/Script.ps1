﻿<#

    .SYNOPSIS
    Creating Hostpool and add sessionhost servers to existing/new Hostpool.

    .DESCRIPTION
    This script add sessionhost servers to existing/new Hostpool
    The supported Operating Systems Windows Server 2016 and Windows 10 multisession.

    .ROLE
    Readers

    #>


param(
  [Parameter(mandatory = $false)]
  [string]$RDBrokerURL,

  [Parameter(mandatory = $true)]
  [string]$TenantGroupName,

  [Parameter(mandatory = $false)]
  [string]$TenantName,

  [Parameter(mandatory = $false)]
  [string]$HostPoolName,

  [Parameter(mandatory = $false)]
  [string]$Description,
  
  [Parameter(mandatory = $false)]
  [string]$FriendlyName,
  
  [Parameter(mandatory = $true)]
  [string]$Hours,

  [Parameter(mandatory = $true)]
  [string]$FileURI,

  [Parameter(mandatory = $false)]
  [string]$TenantAdminUPN,

  [Parameter(mandatory = $false)]
  [string]$TenantAdminPassword,

  [Parameter(mandatory = $true)]
  [string]$localAdminUserName,

  [Parameter(mandatory = $false)]
  [string]$registrationToken,
  
  [Parameter(mandatory = $true)]
  [string]$localAdminPassword,

  [Parameter(mandatory = $true)]
  [string]$rdshIs1809OrLater,
  
  [Parameter(mandatory = $false)]
  [string]$ActivationKey
)

Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope Process -Force -Confirm:$false
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force -Confirm:$false
$PolicyList=Get-ExecutionPolicy -List
$log = $PolicyList | Out-String
$rdshIs1809OrLaterBool = ($rdshIs1809OrLater -eq "True")

function Write-Log {

  [CmdletBinding()]
  param(

    [Parameter(mandatory = $false)]
    [string]$Message,
    [Parameter(mandatory = $false)]
    [string]$Error
  )

  try {
    $DateTime = Get-Date -Format ‘MM-dd-yy HH:mm:ss’
    $Invocation = "$($MyInvocation.MyCommand.Source):$($MyInvocation.ScriptLineNumber)"
    if ($Message) {

      Add-Content -Value "$DateTime - $Invocation - $Message" -Path "$([environment]::GetEnvironmentVariable('TEMP', 'Machine'))\ScriptLog.log"
    }
    else {


      Add-Content -Value "$DateTime - $Invocation - $Error" -Path "$([environment]::GetEnvironmentVariable('TEMP', 'Machine'))\ScriptLog.log"
    }
  }
  catch {



    Write-Error $_.Exception.Message
  }
}

Write-Log -Message "Policy List: $log"

function ActivateWin10
{
  param
  (
    [Parameter(mandatory = $false)]
    [string]$ActivationKey
  )


  cscript c:\windows\system32\slmgr.vbs /ipk $ActivationKey
  dism /online /Enable-Feature /FeatureName:AppServerClient /NoRestart /Quiet
}

#DSC Portion Log
class PsRdsSessionHost
{
  [string]$TenantName = [string]::Empty
  [string]$HostPoolName = [string]::Empty
  [string]$SessionHostName = [string]::Empty
  [int]$TimeoutInMin = 900

  PsRdsSessionHost () {}

  PsRdsSessionHost ([string]$TenantName,[string]$HostPoolName,[string]$SessionHostName) {
    $this.TenantName = $TenantName
    $this.HostPoolName = $HostPoolName
    $this.SessionHostName = $SessionHostName
  }

  PsRdsSessionHost ([string]$TenantName,[string]$HostPoolName,[string]$SessionHostName,[int]$TimeoutInMin) {

    if ($TimeoutInMin -gt 1800)
    {
      Write-Output "TimeoutInMin is too high, maximum value is 1800"

    }

    $this.TenantName = $TenantName
    $this.HostPoolName = $HostPoolName
    $this.SessionHostName = $SessionHostName
    $this.TimeoutInMin = $TimeoutInMin
  }

  hidden [object] _trySessionHost ([string]$operation)
  {
    if ($operation -ne "get" -and $operation -ne "set")
    {
      Write-Output "PsRdsSessionHost: Invalid operation: $operation. Valid Operations are get or set"
    }


    $specificToSet = @{ $true = "-AllowNewSession `$true"; $false = "" }[$operation -eq "set"]
    $commandToExecute = "$operation-RdsSessionHost -TenantName `$this.TenantName -HostPoolName `$this.HostPoolName -Name `$this.SessionHostName -ErrorAction SilentlyContinue $specificToSet"
    $sessionHost = (Invoke-Expression $commandToExecute)

    $StartTime = Get-Date
    while ($sessionHost -eq $null)
    {
      Start-Sleep (60..120 | Get-Random)
      Write-Output "PsRdsSessionHost: Retrying Add SessionHost..."
      $sessionHost = (Invoke-Expression $commandToExecute)

      if ((Get-Date).Subtract($StartTime).Minutes -gt $this.TimeoutInMin)
      {
        if ($sessionHost -eq $null)
        {
          Write-Output "PsRdsSessionHost: An error ocurred while adding session host:`nSessionHost:$this.SessionHostname`nHostPoolName:$this.HostPoolNmae`nTenantName:$this.TenantName`nError Message: $($error[0] | Out-String)"
          return $null
        }
      }
    }
    return $sessionHost
  }
  
  [object] SetSessionHost () {


    if ([string]::IsNullOrEmpty($this.TenantName) -or [string]::IsNullOrEmpty($this.HostPoolName) -or [string]::IsNullOrEmpty($this.HostPoolName))
    {
      return $null
    }
    else
    {

      return ($this._trySessionHost("set"))
    }
  }

  [object] GetSessionHost () {



    if ([string]::IsNullOrEmpty($this.TenantName) -or [string]::IsNullOrEmpty($this.HostPoolName) -or [string]::IsNullOrEmpty($this.HostPoolName))
    {
      return $null
    }
    else
    {
      return ($this._trySessionHost("get"))
    }
  }
}


[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {

  #Downloading the DeployAgent zip file to rdsh vm
  Invoke-WebRequest -Uri $fileURI -OutFile "C:\DeployAgent.zip"
  Write-Log -Message "Downloaded DeployAgent.zip into this location C:\"

  #Creating a folder inside rdsh vm for extracting deployagent zip file
  New-Item -Path "C:\DeployAgent" -ItemType directory -Force -ErrorAction SilentlyContinue
  Write-Log -Message "Created a new folder 'DeployAgent' inside VM"
  Expand-Archive "C:\DeployAgent.zip" -DestinationPath "C:\DeployAgent" -ErrorAction SilentlyContinue
  Write-Log -Message "Extracted the 'Deployagent.zip' file into 'C:\Deployagent' folder inside VM"
  Set-Location "C:\DeployAgent"
  Write-Log -Message "Setting up the location of Deployagent folder"
  #Checking if RDInfragent is registered or not in rdsh vm
  $CheckRegistery = Get-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\RDInfraAgent" -ErrorAction SilentlyContinue

  Write-Log -Message "Checking whether VM was Registered with RDInfraAgent"


  if ($CheckRegistery) {
    Write-Log -Message "VM was already registered with RDInfraAgent, script execution was stopped"

  }
  else {

    Write-Log -Message "VM was not registered with RDInfraAgent, script is executing"

  }

  $AdminSecurepass = ConvertTo-SecureString -String $localAdminPassword -AsPlainText -Force
  $adminCredentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($localAdminUserName,$AdminSecurepass)




  if (!$CheckRegistery) {
    if (!$registrationToken)

    {
      #Importing RDMI PowerShell module
      Import-Module .\PowershellModules\Microsoft.RDInfra.RDPowershell.dll
      Write-Log -Message "Imported RDMI PowerShell modules successfully"
      $Securepass = ConvertTo-SecureString -String $TenantAdminPassword -AsPlainText -Force
      $Credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($TenantAdminUPN,$Securepass)
      


      #Getting fqdn of rdsh vm
      $SessionHostName = (Get-WmiObject win32_computersystem).DNSHostName + "." + (Get-WmiObject win32_computersystem).Domain
      Write-Log -Message "Getting fully qualified domain name of RDSH VM: $SessionHostName"


      # Authenticating to WVD
       $authentication = Add-RdsAccount -DeploymentUrl $RDBrokerURL -Credential $Credentials
       $obj = $authentication | Out-String
      if ($authentication)
      {
        Write-Log -Message "RDMI Authentication successfully Done. Result:`n$obj"
      }
      else
      {
        Write-Log -Error "RDMI Authentication Failed, Error:`n$obj"
      }

      # Set context to the appropriate tenant group
      Write-Log "Running switching to the $TenantGroupName context"
      Set-RdsContext -TenantGroupName $TenantGroupName
      try
      {
        $tenants = Get-RdsTenant -Name $TenantName
        if (!$tenants)
        {
          Write-Log "No tenants exist or you do not have proper access."
        }
      }
      catch
      {
        Write-Log -Message $_
      }


      $HPName = Get-RdsHostPool -TenantName $TenantName -Name $HostPoolName -ErrorAction SilentlyContinue
      Write-Log -Message "Checking Hostpool exists inside the Tenant"


      if ($HPName) {
        $HPName = Get-RdsHostPool -TenantName $TenantName -Name $HostPoolName -ErrorAction SilentlyContinue
        Write-Log -Message "Hostpool exists inside tenant: $TenantName"


        Write-Log -Message "Checking Hostpool UseResversconnect is true or false"
        # Cheking UseReverseConnect is true or false
        if ($HPName.UseReverseConnect -eq $False) {

          Write-Log -Message "Usereverseconnect is false, it will be changed to true"
          Set-RdsHostPool -TenantName $TenantName -Name $HostPoolName -UseReverseConnect $true
        }
        else {
          Write-Log -Message "Hostpool Usereverseconnect already enabled as true"
        }


        #Exporting existed rdsregisterationinfo of hostpool
        $Registered = Export-RdsRegistrationInfo -TenantName $TenantName -HostPoolName $HostPoolName -ErrorAction SilentlyContinue
        $registrationToken = $Registered.Token
        $reglog = $registered | Out-String
        Write-Log -Message "Exported Rds RegisterationInfo into variable 'Registered': $reglog"
        $systemdate = (Get-Date)
        #$Tokenexpiredate = $Registered.ExpirationUtc #June Codebit
        $Tokenexpiredate = $Registered.expirationtime #July Codebit
        $difference = $Tokenexpiredate - $systemdate
        Write-Log -Message "Calculating date and time of expiration with system date and time"
        if ($difference -lt 0 -or $Registered -eq 'null') {
          Write-Log -Message "Registerationinfo expired, creating new registeration info with hours $Hours"
          $Registered = New-RdsRegistrationInfo -TenantName $TenantName -HostPoolName $HostPoolName -ExpirationHours $Hours
          $registrationToken = $Registered.Token
        }
        else {
          $reglogexpired = $Tokenexpiredate | Out-String -Stream
          Write-Log -Message "Registerationinfo not expired and expiring on $reglogexpired"
        }
        #Executing DeployAgent psl file in rdsh vm and add to hostpool
        $DAgentInstall = .\DeployAgent.ps1 -ComputerName $SessionHostName -AgentBootServiceInstaller ".\RDAgentBootLoaderInstall\" -AgentInstaller ".\RDInfraAgentInstall\" -SxSStackInstaller ".\RDInfraSxSStackInstall\" -AdminCredentials $adminCredentials -RegistrationToken $registrationToken -StartAgent $true -rdshIs1809OrLater $rdshIs1809OrLaterBool -EnableSxSStackScriptFile ".\enablesxsstackrc.ps1"
        Write-Log -Message "DeployAgent Script was successfully executed and RDAgentBootLoader,RDAgent,StackSxS installed inside VM for existing hostpool: $HostPoolName `n$DAgentInstall"

      }

      else {
        Write-Log -Message "Hostpool does not exists inside tenant: $TenantName"

        # creating new hostpool
        $Hostpool = New-RdsHostPool -TenantName $TenantName -Name $HostPoolName -Description $Description -FriendlyName $FriendlyName
        $HName = $hostpool.Name | Out-String -Stream
        Write-Log -Message "Successfully created new Hostpool: $HName"

        # setting up usereverseconnect as true
        Write-Log -Message "setting up the UserReverseconnect value as true for Hostpool: $HName"
        Set-RdsHostPool -TenantName $TenantName -Name $HostPoolName -UseReverseConnect $true

        #Registering hostpool with 365 days
        Write-Log -Message "Creating new registeration info for hostpool:$HName with expired hours $Hours"
        $ToRegister = New-RdsRegistrationInfo -TenantName $TenantName -HostPoolName $HostPoolName -ExpirationHours $Hours
        $registrationToken = $ToRegister.Token
        $newRegInfo = $ToRegister.ExpirationUtc | Out-String -Stream
        Write-Log -Message "Successfully registered $HName, expiration date: $newRegInfo"

        #Executing DeployAgent psl file in rdsh vm and add to hostpool
        $DAgentInstall = .\DeployAgent.ps1 -ComputerName $SessionHostName -AgentBootServiceInstaller ".\RDAgentBootLoaderInstall\" -AgentInstaller ".\RDInfraAgentInstall\" -SxSStackInstaller ".\RDInfraSxSStackInstall\" -AdminCredentials $adminCredentials -RegistrationToken $registrationToken -StartAgent $true -rdshIs1809OrLater $rdshIs1809OrLaterBool -EnableSxSStackScriptFile ".\enablesxsstackrc.ps1"

        Write-Log -Message "DeployAgent Script was successfully executed and RDAgentBootLoader, RDAgent, StackSxS installed inside VM for new $HName `n$DAgentInstall"

      }
      #add host vm to hostpool
      [Microsoft.RDInfra.RDManagementData.RdMgmtSessionHost]$addRdsh = ([PsRdsSessionHost]::new($TenantName,$HostPoolName,$SessionHostName)).GetSessionHost()
      Write-Log -Message "host object content: `n$($addRdsh | Out-String)"
      $rdshName = $addRdsh.Name | Out-String -Stream
      $poolName = $addRdsh.HostPoolName | Out-String -Stream
      Write-Log -Message "Successfully added $rdshName VM to $poolName"



    }
    else {
      #Getting fqdn of rdsh vm
      $SessionHostName = (Get-WmiObject win32_computersystem).DNSHostName + "." + (Get-WmiObject win32_computersystem).Domain
      Write-Log -Message "Getting fully qualified domain name of RDSH VM: $SessionHostName"

      #Executing DeployAgent psl file in rdsh vm and add to hostpool
      $DAgentInstall = .\DeployAgent.ps1 -ComputerName $SessionHostName -AgentBootServiceInstaller ".\RDAgentBootLoaderInstall\" -AgentInstaller ".\RDInfraAgentInstall\" -SxSStackInstaller ".\RDInfraSxSStackInstall\" -AdminCredentials $adminCredentials -RegistrationToken $registrationToken -StartAgent $true -rdshIs1809OrLater $rdshIs1809OrLaterBool -EnableSxSStackScriptFile ".\enablesxsstackrc.ps1"
      Write-Log -Message "DeployAgent Script was successfully executed and RDAgentBootLoader,RDAgent,StackSxS installed inside VM for existing hostpool: $HostPoolName `n$DAgentInstall"

      [Microsoft.RDInfra.RDManagementData.RdMgmtSessionHost]$addRdsh = ([PsRdsSessionHost]::new($TenantName,$HostPoolName,$SessionHostName)).GetSessionHost()
      Write-Log -Message "RDSH object content: `n$($addRdsh | Out-String)"
      Write-Log -Message "Successfully added $SessionHostName VM to HostPool"
    }


  }

}
catch {
  Write-Log -Error $_.Exception.Message

}
if ($rdshIs1809OrLaterBool) {
  Write-Log -Message "Activating Windows 10 Evd"
  ActivateWin10 -ActivationKey $ActivationKey

  Write-Log -Message "Rebooting VM"
  Shutdown -r -t 90
}
