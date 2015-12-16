<#
.Synopsis
   Aautomate cleaning up a C: drive with low disk space
.DESCRIPTION
   Looks for any disconnected remote sessions and logs them off
   Cleans the C: drive's Window Temperary files, Windows SoftwareDistribution folder, `
   the local users Temperary folder, IIS logs(if applicable) and empties the recycling bin. `

   All deleted files will go into a log transcript on the Desktop of the user running the script. By default this `
   script leaves files that are newer than 7 days old however this variable can be edited.
.EXAMPLE
   PS C:\Users\mkerfoot\Desktop\Powershell> .\cleanup_log.ps1
   Save the file to your desktop with a .PS1 extention and run the file from an elavated PowerShell prompt.
.NOTES
   This script will typically clean up anywhere from 1GB up to 15GB of space from a C: drive.
.FUNCTIONALITY
   PowerShell v3
#>

$TimeStamp = (Get-Date -UFormat "%A, %b %d, %Y %r"| foreach {$_ -replace ":", "."})
$Version = ([system.environment]::osversion).version.tostring()

#Log Off Disconnected Sessions
Function LogOff {
$TSLogFile = "$env:USERPROFILE\Desktop\Sessions " + $TimeStamp + ".log"
function Write-Log([string]$message)
{
   Out-File -InputObject $message -FilePath $TSLogFile -Append
}
 
function Get-Sessions
{
   $queryResults = query session
   $starters = New-Object psobject -Property @{"SessionName" = 0; "UserName" = 0; "ID" = 0; "State" = 0; "Type" = 0; "Device" = 0;}
   foreach ($result in $queryResults)
   {
      try
      {
         if($result.trim().substring(0, $result.trim().indexof(" ")) -eq "SESSIONNAME")
         {
            $starters.UserName = $result.indexof("USERNAME");
            $starters.ID = $result.indexof("ID");
            $starters.State = $result.indexof("STATE");
            $starters.Type = $result.indexof("TYPE");
            $starters.Device = $result.indexof("DEVICE");
            continue;
         }
 
         New-Object psobject -Property @{
            "SessionName" = $result.trim().substring(0, $result.trim().indexof(" ")).trim(">");
            "Username" = $result.Substring($starters.Username, $result.IndexOf(" ", $starters.Username) - $starters.Username);
            "ID" = $result.Substring($result.IndexOf(" ", $starters.Username), $starters.ID - $result.IndexOf(" ", $starters.Username) + 2).trim();
            "State" = $result.Substring($starters.State, $result.IndexOf(" ", $starters.State)-$starters.State).trim();
            "Type" = $result.Substring($starters.Type, $starters.Device - $starters.Type).trim();
            "Device" = $result.Substring($starters.Device).trim()
         }
      } 
      catch 
      {
         $e = $_;
         Write-Log "ERROR: " + $e.PSMessageDetails
      }
   }
}
 
[string]$IncludeStates = '^(Disc)$'
Write-Log -Message "Disconnected Sessions CleanUp"
Write-Log -Message "============================="
$DisconnectedSessions = Get-Sessions | ? {$_.State -match $IncludeStates -and $_.UserName -ne ""} | Select ID, UserName
Write-Log -Message "Logged off sessions"
Write-Log -Message "-------------------"
foreach ($session in $DisconnectedSessions)
{
   logoff $session.ID
   Write-Log -Message $session.Username
}
Write-Log -Message " "
Write-Log -Message "Finished"
} 

#Cleanup Disk
Function Cleanup {
function global:Write-Verbose ( [string]$Message )

# check $VerbosePreference variable, and turns -Verbose on
{ if ( $VerbosePreference -ne 'SilentlyContinue' )
{ Write-Host " $Message" -ForegroundColor 'Yellow' } }

$VerbosePreference = "Continue"
$DaysToDelete = 7
$objShell = New-Object -ComObject Shell.Application 
$objFolder = $objShell.Namespace(0xA)
$ErrorActionPreference = "silentlycontinue"

#Start-Transcript -Path Current Users Desktop  
Start-Transcript -Path "$env:UserProfile\Desktop\$env:ComputerName Disk Cleanup.log" 
                  
## Cleans all code off of the screen.
Clear-Host

## Lists large files based on extension in Users Directories.
$size = Get-ChildItem C:\Users\* -Include *.iso, *.vhd -Recurse -ErrorAction SilentlyContinue | 
Sort Length -Descending | 
Select-Object Name, Directory,
@{Name="Size (GB)";Expression={ "{0:N2}" -f ($_.Length / 1GB) }} |
Format-Table -AutoSize | Out-String

## Creates before cleanup baseline to display in log.
$Before = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq "3" } | Select-Object SystemName,
@{ Name = "Drive" ; Expression = { ( $_.DeviceID ) } },
@{ Name = "Size (GB)" ; Expression = {"{0:N1}" -f( $_.Size / 1gb)}},
@{ Name = "FreeSpace (GB)" ; Expression = {"{0:N1}" -f( $_.Freespace / 1gb ) } },
@{ Name = "PercentFree" ; Expression = {"{0:P1}" -f( $_.FreeSpace / $_.Size ) } } |
Format-Table -AutoSize | Out-String                      
                    
## Stops the windows update service. 
Get-Service -Name wuauserv | Stop-Service -Force -Verbose -ErrorAction SilentlyContinue
## Windows Update Service has been stopped successfully!

## Deletes the contents of windows software distribution.
Get-ChildItem "C:\Windows\SoftwareDistribution\*" -Recurse -Force -Verbose -ErrorAction SilentlyContinue |
Where-Object { ($_.CreationTime -lt $(Get-Date).AddDays(-$DaysToDelete)) } |
remove-item -force -Verbose -recurse -ErrorAction SilentlyContinue
## The Contents of Windows SoftwareDistribution have been removed successfully!

## Deletes the contents of the Windows Temp folder.
Get-ChildItem "C:\Windows\Temp\*" -Recurse -Force -Verbose -ErrorAction SilentlyContinue |
Where-Object { ($_.CreationTime -lt $(Get-Date).AddDays(-$DaysToDelete)) } |
remove-item -force -Verbose -recurse -ErrorAction SilentlyContinue
## The Contents of Windows Temp have been removed successfully!
             
## Deletes all files and folders in user's Temp folder. 
Get-ChildItem "C:\users\*\AppData\Local\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue |
Where-Object { ($_.CreationTime -lt $(Get-Date).AddDays(-$DaysToDelete))} |
remove-item -force -Verbose -recurse -ErrorAction SilentlyContinue
## The contents of C:\users\$env:USERNAME\AppData\Local\Temp\ have been removed successfully!
                    
## Removes all files and folders in user's Temporary Internet Files. 
Get-ChildItem "C:\users\*\AppData\Local\Microsoft\Windows\Temporary Internet Files\*" `
-Recurse -Force -Verbose -ErrorAction SilentlyContinue |
Where-Object {($_.CreationTime -le $(Get-Date).AddDays(-$DaysToDelete))} |
remove-item -force -recurse -ErrorAction SilentlyContinue
## All Temporary Internet Files have been removed successfully!
 
## Cleans IIS Logs if applicable.
Get-ChildItem "C:\inetpub\logs\LogFiles\*" -Recurse -Force -ErrorAction SilentlyContinue |
Where-Object { ($_.CreationTime -le $(Get-Date).AddDays(-7)) } |
Remove-Item -Force -Verbose -Recurse -ErrorAction SilentlyContinue
## All IIS Logfiles over x days old have been removed Successfully!

## Deletes all log files in C:\ larger than 5MB.
Get-ChildItem -path "C:\" -Recurse -Force -Verbose -ErrorAction SilentlyContinue -include ("*.log", "*.txt") | 
Where-Object {$_.Length -gt 5MB} |
Remove-Item -Recurse -Force -Verbose -ErrorAction SilentlyContinue
## All log files in C:\ larger than 5MB have been removed successfully!
                  
## Empties the contents of the recycling bin.
The Recycling Bin is now being emptied!
$objFolder.items() | ForEach-Object { Remove-Item $_.path -ErrorAction Ignore -Force -Verbose -Recurse }
## The Recycling Bin has been emptied!

## Starts the Windows Update Service
##Get-Service -Name wuauserv | Start-Service -Verbose

## Creates after cleanup comparison  to display in log.
$After =  Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq "3" } | Select-Object SystemName,
@{ Name = "Drive" ; Expression = { ( $_.DeviceID ) } },
@{ Name = "Size (GB)" ; Expression = {"{0:N1}" -f( $_.Size / 1gb)}},
@{ Name = "FreeSpace (GB)" ; Expression = {"{0:N1}" -f( $_.Freespace / 1gb ) } },
@{ Name = "PercentFree" ; Expression = {"{0:P1}" -f( $_.FreeSpace / $_.Size ) } } |
Format-Table -AutoSize | Out-String

## Combines before and after info for ticketing purposes
Hostname ; Get-Date | Select-Object DateTime
Write-Verbose "Before: $Before"
Write-Verbose "After: $After"
Write-Verbose $size

## Completed Successfully!
Stop-Transcript } 


If ($Version -ge "6.3.9600.0") {
    LogOff
    Cleanup
}
Else {
Cleanup
}