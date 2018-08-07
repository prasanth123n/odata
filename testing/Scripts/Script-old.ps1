﻿Param(
      
    [Parameter(Mandatory = $True)]
    [ValidateNotNullOrEmpty()]
    [string] $SubscriptionId,
         
    [Parameter(Mandatory = $True)]
    [String] $Username,

    [Parameter(Mandatory = $True)]
    [string] $Password,

    [Parameter(Mandatory = $True)]
    [string] $FileURI,

    [Parameter(Mandatory = $True)]
    [string] $resourceGroupName
 
)

function Disable-ieESC {
    $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
    $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
    Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0
    Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0
    Stop-Process -Name Explorer
    Write-Host "IE Enhanced Security Configuration (ESC) has been disabled." -ForegroundColor Green
}

Disable-ieESC


Invoke-WebRequest -Uri $FileURI -OutFile "C:\PSModules.zip"
New-Item -Path "C:\PSModules" -ItemType directory -Force -ErrorAction SilentlyContinue
Expand-Archive "C:\PSModules.zip" -DestinationPath "C:\PSModules" -ErrorAction SilentlyContinue
Set-Location "C:\PSModules"

    Start-Job -ScriptBlock {
    param($SubscriptionId,$Username,$Password,$resourceGroupName)
    Start-Process PowerShell -NoProfile -ExecutionPolicy Bypass -Command "& 'C:\PSModules\RemoveRG.ps1' -SubscriptionId $SubscriptionId -Username $Username -Password $Password -resourceGroupName $resourceGroupName" | Invoke-Expression
    } -ArgumentList($SubscriptionId,$Username,$Password,$resourceGroupName)
    
    