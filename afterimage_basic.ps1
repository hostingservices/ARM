$ComputerName=$ENV:ComputerName
########create logfile###################
$ErrorActionPreference="SilentlyContinue"
Stop-Transcript | out-null
$ErrorActionPreference = "Continue"
Start-Transcript -path C:\$ComputerName"_"$(Get-Date -format 'ddMMyyyy')_initialconfig.txt -append
#create all functions
Function Create-Partitions {
	$drives = gwmi Win32_diskdrive
	$scriptdisk = $Null
	$script = $Null
	foreach ($disk in $drives){
		if ($disk.Partitions -eq "0"){
			$drivenumber = $disk.DeviceID -replace '[\\\\\.\\physicaldrive]',''
			$script = @"
select disk $drivenumber
online disk noerr
attributes disk clear readonly noerr
convert GPT NOERR
create partition primary noerr
format FS=NTFS QUICK NOERR
assign NOERR
"@
		}
		$drivenumber = $Null
		$scriptdisk += $script + "`n"
	}
	$scriptdisk | diskpart |out-null
}

function Set-DriveLetter($oldletter, $newletter) {
	Write-Host "::: Changing the driveletter from" $oldletter "to" $newletter "..." -ForegroundColor Yellow
	$objDisk = (Get-WmiObject -Class win32_volume|Where-Object {$_.Name -ieq $oldletter + "\"})
	$objdiskid = $objDisk.DeviceID
	Write-Host "    The Device ID of" $oldletter "is" $objdiskid
	$Volume=(mountvol $objDiskid /l).trim()
	mountvol $oldletter /d |Out-Null
	mountvol $newletter $Volume |Out-Null
	$ChangedDisk = (Get-WmiObject -Class win32_volume|Where-Object {$_.Name -ieq $newletter + "\"})
	if ($ChangedDisk.DeviceID -ieq $Volume) {
		Write-Host "    The Drive letter is succesfully changed from" $oldletter "to" $newletter -ForegroundColor Green
	}
	else { 
		Write-Host "    The Drive letter could not changed from" $oldletter "to" $newletter -ForegroundColor Red
	}
	Write-Host `n
}

function Set-DriveLabel($letter, $label) {
	Write-Host "::: Changing the disklabel of" $letter "to" $label "..." -ForegroundColor Yellow
	#if (!(Test-Path $letter)) {
	#	Throw "Drive $letter does not exist."
	#}
	$instance = ([wmi]"Win32_LogicalDisk='$letter'")
	$instance.VolumeName = $label
	$instance.Put()| out-null
	if ($instance.VolumeName -ieq $label) {
		Write-Host "    The Disklabel of" $letter "is succesfully set to" $label -ForegroundColor Green
	}
	else {
		Write-Host "    The Disklabel of" $letter "could not be set to" $label "current disklabel is:" $instance.VolumeName -ForegroundColor Red
	}
	Write-Host `n
}

function Get-MemoryUsage ($ComputerName=$ENV:ComputerName) {
 
if (Test-Connection -ComputerName $ComputerName -Count 1 -Quiet) {
 $ComputerSystem = Get-WmiObject -ComputerName $ComputerName -Class Win32_operatingsystem -Property CSName, TotalVisibleMemorySize, FreePhysicalMemory
 $MachineName = $ComputerSystem.CSName
 $FreePhysicalMemory = ($ComputerSystem.FreePhysicalMemory) / (1mb)
 $TotalVisibleMemorySize = ($ComputerSystem.TotalVisibleMemorySize) / (1kb)
 $TotalVisibleMemorySizeR = “{0:N2}” -f $TotalVisibleMemorySize
 $TotalFreeMemPerc = ($FreePhysicalMemory/$TotalVisibleMemorySize)*100
 $TotalFreeMemPercR = “{0:N2}” -f $TotalFreeMemPerc
 $RAM2 = $TotalVisibleMemorySize
 $global:pagefile= [Math]::Round($RAM2 * 1.5)

} }

function Set-PageFile($location, $size) {
	Write-Host "::: Placing PageFile on" $location "with a fixed size of" $size "MB" -ForegroundColor Yellow
	$NewPageFile=($location + "\pagefile.sys")
	$RAM = [Math]::Round((Get-WmiObject Win32_OperatingSystem).TotalVisibleMemorySize / 1kb)
	$global:PageFile2 = [uint32]($RAM * 1.5)
	$System = (Get-WmiObject Win32_ComputerSystem -EnableAllPrivileges)
	$System.AutomaticManagedPagefile = $False
	$System.Put() |Out-Null
	Set-WmiInstance -class Win32_PageFileSetting -Arguments @{Name=$NewPageFile} |Out-Null
	$PageFileSetting=(Get-WmiObject -class Win32_PageFileSetting | Where-Object {$_.Name -ieq $NewPageFile})
	$PageFileSetting.InitialSize=$size
	$PageFileSetting.MaximumSize=$size
	$PageFileSetting.Put() |Out-Null
	(Get-WmiObject -class Win32_PageFileSetting | Where-Object {$_.Name -ieq "C:\pagefile.sys"}).Delete()|out-null
	$PageFileApplied=(Get-WmiObject -class Win32_PageFileSetting)
	if ($PageFileApplied.Name -ieq $NewPageFile -and $PageFileApplied.InitialSize -eq $size -and $PageFileApplied.MaximumSize -eq $size) {
		Write-Host "    Succesfully placed a" $size "MB Pagefile on" $location -ForegroundColor Green
	}
	else {
		Write-Host "    An error occured creating a" $size "MB Pagefile on" $location -ForegroundColor Red
	}
	Write-Host `n
}

#start script
#create partition for new disk
Create-Partitions | Out-Host

#CD-ROM to Z: 
$CDDrive = (Get-WmiObject -Class Win32_CDRomDrive).drive
Set-DriveLetter $CDDrive Z: | Out-Host
Start-Sleep 5
#Data to E: and set drivelabels
Set-DriveLetter F: E: | Out-Host
			Start-Sleep 5
			Set-DriveLabel C: SYSTEM | Out-Host
			Set-DriveLabel D: Pagefile | Out-Host
			Set-DriveLabel E: DATA | Out-Host

#edit fixed Pagefile
Get-MemoryUsage | Out-Host
Set-Pagefile D: $pagefile

#Enable remote on Servers
netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes
netsh advfirewall firewall set rule group="Remote Administration" new enable=yes
netsh advfirewall firewall set rule group="Remote Service Management" new enable=yes
netsh advfirewall firewall set rule group="Performance Logs and Alerts" new enable=yes
Netsh advfirewall firewall set rule group="Remote Event Log Management" new enable=yes
Netsh advfirewall firewall set rule group="Remote Scheduled Tasks Management" new enable=yes

#Enable WinRM
winrm quickconfig -q
netsh advfirewall firewall set rule name="Windows Remote Management (HTTP-In)" new enable=Yes

#Enable WMI Firewall Exception on Servers
netsh advfirewall firewall set rule group="Windows Management Instrumentation (WMI)" new enable=Yes

#Disable VMICTimeProvider
$RegKey ="HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\VMICTimeProvider"
Set-ItemProperty -Path $RegKey -Name Enabled -Value 0 -Type DWord
net stop w32time | net start w32time | w32tm /resync /rediscover | out-null | w32tm /query /source | Out-Host

#Disable IE Enhanced Security Configuration (ESC)
function Disable-IEESC
{
$AdminKey = “HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}”
$UserKey = “HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}”
Set-ItemProperty -Path $AdminKey -Name “IsInstalled” -Value 0 -Force
Set-ItemProperty -Path $UserKey -Name “IsInstalled” -Value 0 -Force
Stop-Process -Name Explorer -Force
Write-Host “IE Enhanced Security Configuration (ESC) has been disabled.” -ForegroundColor Green | Out-Host
}
Disable-IEESC

#make 'temp' directory on C:\
mkdir c:\Temp

#end log
Stop-Transcript