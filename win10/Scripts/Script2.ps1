﻿Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope Process -Force -Confirm:$false
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force -Confirm:$false
$PolicyList=Get-ExecutionPolicy -List
$log = $PolicyList | Out-String
Write-Output $log

Invoke-WebRequest -Uri $FileURI -OutFile "C:\DeployAgent.zip"
    #Write-Log -Message "Downloaded DeployAgent.zip into this location C:\"

    #Creating a folder inside rdsh vm for extracting deployagent zip file
    New-Item -Path "C:\DeployAgent" -ItemType directory -Force -ErrorAction SilentlyContinue
    #Write-Log -Message "Created a new folder 'DeployAgent' inside VM"
    Expand-Archive "C:\DeployAgent.zip" -DestinationPath "C:\DeployAgent" -ErrorAction SilentlyContinue
    #Write-Log -Message "Extracted the 'Deployagent.zip' file into 'C:\Deployagent' folder inside VM"
    Set-Location "C:\DeployAgent"
    #Write-Log -Message "Setting up the location of Deployagent folder
   .\Script.ps1 -FileURI $FileURI -registrationToken $registrationToken -ActivationKey $ActivationKey -rdshIs1809OrLater $rdshIs1809OrLater -localAdminUserName $localAdminUserName -localAdminPassword $localAdminPassword

