cls
#input data
$VMMServer = "server"
$finish_cycle=0
$Array_part_VMHosts=@()
$VMHosts = Get-SCVMHost -VMMServer $VMMServer | select Name,VirtualizationPlatform,DiskVolumes  | Sort-Object VirtualizationPlatform,name
for($i=0; $i -lt $VMHosts.Count; $i+=3){ 
    $Array_part_VMHosts += ,@($VMHosts[$i..($i+2)]);
}

# Parent синхронизированная хэш-таблица Hyper-V
$Parent_Hash = [HashTable]::Synchronized(@{ finish_cycle=$finish_cycle })
$Parent_Runspace = [RunSpaceFactory]::CreateRunspace()
$Parent_Runspace.ApartmentState = "STA"
$Parent_Runspace.ThreadOptions = "ReuseThread"
$Parent_Runspace.Open()
$Parent_Runspace.SessionStateProxy.setVariable("Parent_Hash", $Parent_Hash)
$Parent_PowerShell = [PowerShell]::Create()
$Parent_PowerShell.Runspace = $Parent_Runspace
$Parent_PowerShell.AddScript({ while ($true) { start-sleep -Seconds 15 } }).BeginInvoke()

for($n=0; $n -lt $Array_part_VMHosts.Count; $n++){
    #if($HyperV_Hash.Array_part_VMHosts[$n] -and $HyperV_Hash.Number_Hosts -eq $Number_Hosts_eq){
        # Children синхронизированная хэш-таблица
        $Children_Hash = [HashTable]::Synchronized(@{ Array_part_VMHosts=$Array_part_VMHosts;VMMServer = $VMMServer;n=$n;Parent_Hash=$Parent_Hash})
        $Children_Runspace = [RunSpaceFactory]::CreateRunspace()
        $Children_Runspace.ApartmentState = "STA"
        $Children_Runspace.ThreadOptions = "ReuseThread"
        $Children_Runspace.Open()
        $Children_Runspace.SessionStateProxy.setVariable("Children_Hash", $Children_Hash)
        $Children_PowerShell = [PowerShell]::Create()
        $Children_PowerShell.Runspace = $Children_Runspace
        $Children_PowerShell.AddScript({

            #$CustomIP = Get-SCCustomProperty -VMMServer $Children_Hash.VMMServer -Name "IP"
            $CustomVLAN = Get-SCCustomProperty -VMMServer $Children_Hash.VMMServer -Name "VLAN"
            $CustomSCCMClient = Get-SCCustomProperty -VMMServer $Children_Hash.VMMServer -Name "KVP_SCCMClient"
            $CustomSectorSize_KVP = Get-SCCustomProperty -VMMServer $Children_Hash.VMMServer -Name "KVP_SectorSize"
            $CustomSectorSize = Get-SCCustomProperty -VMMServer $Children_Hash.VMMServer -Name "SectorSize"
            $CustomLocation = Get-SCCustomProperty -VMMServer $Children_Hash.VMMServer -Name "Location"
            $CustomVirtualizationPlatform = Get-SCCustomProperty -VMMServer $Children_Hash.VMMServer -Name "VirtualizationPlatform"
            $CustomVMCheckpoints = Get-SCCustomProperty -VMMServer $Children_Hash.VMMServer -Name "VMCheckpoints"

            #Description
            $Custom_App = Get-SCCustomProperty -VMMServer $Children_Hash.VMMServer -Name "ИС"
            $Custom_Env = Get-SCCustomProperty -VMMServer $Children_Hash.VMMServer -Name "Окружение"
            $Custom_OwnerVM = Get-SCCustomProperty -VMMServer $Children_Hash.VMMServer -Name "Ответственный за ВМ"
            $Custom_OwnerApp = Get-SCCustomProperty -VMMServer $Children_Hash.VMMServer -Name "Ответственный за ИС"
            $Custom_Project = Get-SCCustomProperty -VMMServer $Children_Hash.VMMServer -Name "Проект"
            $Custom_Role = Get-SCCustomProperty -VMMServer $Children_Hash.VMMServer -Name "Роль"
            #get Uptime inform
            Function GetUpTime {
	            param([string] $LastBootTime)
	            $Uptime = (Get-Date) - [System.Management.ManagementDateTimeconverter]::ToDateTime($LastBootTime)
	            "$($Uptime.Days).$($Uptime.Hours):$($Uptime.Minutes):$($Uptime.Seconds)" 
            }
            #convert data HTML to string
            filter Import-CimXml{
                $CimXml = [Xml]$_
                $CimObj = New-Object -TypeName System.Object
                foreach ($CimProperty in $CimXml.SelectNodes("/INSTANCE/PROPERTY")){
                $CimObj | Add-Member -MemberType NoteProperty -Name $CimProperty.NAME -Value $CimProperty.VALUE
                }
                $CimObj
            }
            foreach ( $VMHost in $Children_Hash.Array_part_VMHosts[$Children_Hash.n]) {
                if($VMHost.VirtualizationPlatform -eq "HyperV"){
                    $VMs = Get-SCVirtualMachine -VMMServer $Children_Hash.VMMserver -VMHost $VMHost.name | Sort-Object name
                    foreach ( $VM in $VMs ) {
                        $Change_VM = $false
                        $VMname = $VM.name
                        <#IP-Addresses
                        $VM_Network = Get-SCVirtualMachine -VMMServer $Children_Hash.VMMserver -Name $VM.name | Get-SCVirtualNetworkAdapter | Select-Object IPv4Addresses,VLanID
                        $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomIP	        
                        if([string]::IsNullOrEmpty($VM_Network.IPv4Addresses)){
                            if(![string]::IsNullOrEmpty($Custom_Value)){
                                Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                if($?){$Change_VM = $true}
                            }
	                    }else{
                            $IP = [string]$VM_Network.IPv4Addresses -Replace " ",", "
                            if($Custom_Value.Value -ne $IP){
		                        Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomIP -Value $IP
                                if($?){$Change_VM = $true}
                            }
                        }#>
                        #IP-VLAN
                        $VM_Network = Get-SCVirtualMachine -VMMServer $Children_Hash.VMMserver -Name $VM.name | Get-SCVirtualNetworkAdapter | Select-Object IPv4Addresses,VLanID
                        $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomVLAN
                        if([string]::IsNullOrEmpty($VM_Network.VLanID)){
                            if(![string]::IsNullOrEmpty($Custom_Value)){
                                Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                if($?){$Change_VM = $true}
                            }
                        }else{
                            $VLAN = [string]$VM_Network.VLanID -Replace " ",", "
                            if($Custom_Value.Value -ne $VLAN){
                                Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomVLAN -Value $VLAN
                                if($?){$Change_VM = $true}
                            }
                        }
                #KVP----------------------------------------------------------------
                        #KVP Status SCCM client
                        $SCCMClient = ""
                        $VMConf = Get-WmiObject -ComputerName $VMHost.name -Namespace "root\virtualization\v2" -Query "SELECT * FROM Msvm_ComputerSystem WHERE ElementName like '$VMName' "
                        $KVPData = Get-WmiObject -ComputerName $VMHost.name -Namespace "root\virtualization\v2" -Query "Associators of {$VMConf} Where AssocClass=Msvm_SystemDevice ResultClass=Msvm_KvpExchangeComponent"
                        $SCCMClient = $KVPData.GuestExchangeItems | Import-CimXml | select name,data | where {$_.name -eq "SCCMClient"}
                        $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomSCCMClient
                        if([string]::IsNullOrEmpty($SCCMClient)){
                            if(![string]::IsNullOrEmpty($Custom_Value)){
                                Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                if($?){$Change_VM = $true}
                            }
	                    }else{
                            if($Custom_Value.Value -ne $SCCMClient.data){
	                            Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomSCCMClient -Value $SCCMClient.data
                                if($?){$Change_VM = $true}
                            }
	                    }
                        <##KVP SectorSize
                        $SectorSize = ""
                        $VMConf = Get-WmiObject -ComputerName $VMHost.name -Namespace "root\virtualization\v2" -Query "SELECT * FROM Msvm_ComputerSystem WHERE ElementName like '$VMName' "
                        $KVPData = Get-WmiObject -ComputerName $VMHost.name -Namespace "root\virtualization\v2" -Query "Associators of {$VMConf} Where AssocClass=Msvm_SystemDevice ResultClass=Msvm_KvpExchangeComponent"
                        $SectorSize = $KVPData.GuestExchangeItems | Import-CimXml | select name,data | where {$_.name -eq "SectorSize"}
                        if([string]::IsNullOrEmpty($SectorSize)){
	                        $CustomPropValue = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomSectorSize_KVP
                            if(![string]::IsNullOrEmpty($CustomPropValue)){Remove-SCCustomPropertyValue -CustomPropertyValue $CustomPropValue}
	                    }else{
	                        Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomSectorSize_KVP -Value $SectorSize.data
	                    }#>
                #KVP--------------------------------------------------------
                        #SectorSize
                        $SectorSize = ""
                        $VMDisks = $VM | select -ExpandProperty VirtualHardDisks | select -ExpandProperty location
                        $VMDisks | %{
                            $disk = Get-VHD -ComputerName $VMHost.name -Path $_
	                        #512
	                        if($disk.LogicalSectorSize -eq 512 -and $disk.PhysicalSectorSize -eq 512){
		                        if($SectorSize){$SectorSize += "; 512n"}else{$SectorSize = "512n"}
	                        }
	                        #512e
	                        elseif($disk.LogicalSectorSize -eq 512 -and $disk.PhysicalSectorSize -eq 4096){
		                        if($SectorSize){$SectorSize += "; 512e"}else{$SectorSize = "512e"}
	                        }
	                        #4096
	                        elseif($disk.LogicalSectorSize -eq 4096 -and $disk.PhysicalSectorSize -eq 4096){
		                        if($SectorSize){$SectorSize += "; 4kn"}else{$SectorSize = "4kn"}
	                        }
                        }
                        $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomSectorSize
                        if([string]::IsNullOrEmpty($SectorSize)){
                            if(![string]::IsNullOrEmpty($Custom_Value)){
                                Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                if($?){$Change_VM = $true}
                            }
	                    }else{
                            if($Custom_Value.Value -ne $SectorSize){
	                            Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomSectorSize -Value $SectorSize
                                if($?){$Change_VM = $true}
                            }
	                    }
                        #Location
                        $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomLocation
                        if([string]::IsNullOrEmpty($VM.DiskResources.name)){
                            if(![string]::IsNullOrEmpty($VM.Location)){
                                $DiskVolumes = $VMHost.DiskVolumes | select  name,Volumelabel
                                $DiskVolumes | %{
                                    if($_.name.Split("\")[2] -eq $VM.Location.Split("\")[2]){
                                        if($Custom_Value.Value -ne $_.Volumelabel -and ![string]::IsNullOrEmpty($_.Volumelabel)){
                                            Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomLocation -Value $_.Volumelabel
                                            if($?){$Change_VM = $true}
                                        }
                                    }
                                }
                            }else{
                                if(![string]::IsNullOrEmpty($Custom_Value)){
                                    Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                    if($?){$Change_VM = $true}
                                }
                            }
                        }else{
                            if($Custom_Value.Value -ne $VM.DiskResources.name){
                                Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomLocation -Value $VM.DiskResources.name
                                if($?){$Change_VM = $true}
                            }
                        }
                        <#if([string]::IsNullOrEmpty($VM.Location)){
                            if(![string]::IsNullOrEmpty($Custom_Value)){
                                Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                if($?){$Change_VM = $true}
                            }
                        }else{
                            $DiskVolumes = $VMHost.DiskVolumes | select  name,Volumelabel
                            $DiskVolumes | %{
                                if($_.name.Split("\")[2] -eq $VM.Location.Split("\")[2]){
                                    if($Custom_Value.Value -ne $_.Volumelabel){
                                        Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomLocation -Value $_.Volumelabel
                                        if($?){$Change_VM = $true}
                                    }
                                }
                            }
                        }#>
                        #VirtualizationPlatform
                        $VirtualizationPlatform=$VMHost.VirtualizationPlatform
                        $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomVirtualizationPlatform
                        if($Custom_Value.Value -ne $VirtualizationPlatform -and ![string]::IsNullOrEmpty($VirtualizationPlatform)){
                            Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomVirtualizationPlatform -Value $VirtualizationPlatform
                            if($?){$Change_VM = $true}
                        }
                        #VMCheckpoints
                        $VMCheckpoints=$VM.VMCheckpoints.count
                        $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomVMCheckpoints
                        if($VMCheckpoints -eq 0){
                            if(![string]::IsNullOrEmpty($Custom_Value)){
                                Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                if($?){$Change_VM = $true}
                            }
                        }else{
                            if($Custom_Value.Value -ne $VMCheckpoints){
                                Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomVMCheckpoints -Value $VMCheckpoints
                                if($?){$Change_VM = $true}
                            }
                        }
                        #Description
                        $VM.Description.split("`n") | foreach {
                            $description_to_custom = ""
                            if($_ -match "^ИС"){
                                $description_to_custom = $_ -replace "^ИС: ","";
                                $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_App
                                if([string]::IsNullOrEmpty($description_to_custom)){
                                    Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                    if($?){$Change_VM = $true}
                                }else{
                                    if($Custom_Value.Value -ne $description_to_custom){
                                        Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_App -Value $description_to_custom
                                        if($?){$Change_VM = $true}
                                    }
                                }
                            }elseif($_ -match "^Окружение"){
                                $description_to_custom = $_ -replace "^Окружение: ","";
                                $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_Env
                                if([string]::IsNullOrEmpty($description_to_custom)){
                                    #$Custom_Env_remove = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_Env
                                    Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                    if($?){$Change_VM = $true}
                                }else{
                                    if($Custom_Value.Value -ne $description_to_custom){
                                        Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_Env -Value $description_to_custom
                                        if($?){$Change_VM = $true}
                                    }
                                }
                            }elseif($_ -match "^Ответственный за ВМ"){
                                $description_to_custom = $_ -replace "^Ответственный за ВМ: ","";
                                $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_OwnerVM
                                if([string]::IsNullOrEmpty($description_to_custom)){
                                    #$Custom_OwnerVM_remove = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_OwnerVM
                                    Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                    if($?){$Change_VM = $true}
                                }else{
                                    if($Custom_Value.Value -ne $description_to_custom){
                                        Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_OwnerVM -Value $description_to_custom
                                        if($?){$Change_VM = $true}
                                    }
                                }
                            }elseif($_ -match "^Ответственный за ИС"){
                                $description_to_custom = $_ -replace "^Ответственный за ИС: ","";
                                $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_OwnerApp
                                if([string]::IsNullOrEmpty($description_to_custom)){
                                    #$Custom_OwnerApp_remove = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_OwnerApp
                                    Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                    if($?){$Change_VM = $true}
                                }else{
                                    if($Custom_Value.Value -ne $description_to_custom){
                                        Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_OwnerApp -Value $description_to_custom
                                        if($?){$Change_VM = $true}
                                    }
                                }
                            }elseif($_ -match "^Проект"){
                                $description_to_custom = $_ -replace "^Проект: ","";
                                $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_Project
                                if([string]::IsNullOrEmpty($description_to_custom)){
                                    #$Custom_Project_remove = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_Project
                                    Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                    if($?){$Change_VM = $true}
                                }else{
                                    if($Custom_Value.Value -ne $description_to_custom){
                                        Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_Project -Value $description_to_custom
                                        if($?){$Change_VM = $true}
                                    }
                                }
                            }elseif($_ -match "^Роль"){
                                $description_to_custom = $_ -replace "^Роль: ","";
                                $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_Role
                                if([string]::IsNullOrEmpty($description_to_custom)){
                                    #$Custom_Role_remove = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_Role
                                    Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                    if($?){$Change_VM = $true}
                                }else{
                                    if($Custom_Value.Value -ne $description_to_custom){
                                        Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_Role -Value $description_to_custom
                                        if($?){$Change_VM = $true}
                                    }
                                }
                            }
                        }
                        #Update VM
                        if($Change_VM){Refresh-VM -VM $VMName}
                    }
                }else{
                    #input data VMWare
                    $VMWareServer = "Server"
                    $password = ConvertTo-SecureString 'Password' -AsPlainText -Force
                    $cred = New-Object System.Management.Automation.PSCredential ("Username", $password)
                    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
                    #Connect to VMWare
                    Connect-VIServer -Server $VMWareServer -Credential $cred
                    $VMs = Get-SCVirtualMachine -VMMServer $Children_Hash.VMMserver -VMHost $VMHost.name | Sort-Object name
                    foreach ( $VM in $VMs ) {
                        $Change_VM = $false
                        $VMname = $VM.name
                        #VirtualizationPlatform---------------------------------------------------------------------------
                        $VirtualizationPlatform=$VMHost.VirtualizationPlatform
                        $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomVirtualizationPlatform
                        if($Custom_Value.Value -ne $VirtualizationPlatform -and ![string]::IsNullOrEmpty($VirtualizationPlatform)){
                            Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomVirtualizationPlatform -Value $VMHost.VirtualizationPlatform
                            if($?){$Change_VM = $true}
                        }
                        #SectorSize---------------------------------------------------------------------------------------
                        #$VMDisks = Get-SCVirtualMachine -VMMServer czfvmm01 -Name $VMname
                        $SectorSize = ""
                        $VMDisk = $VM | select -ExpandProperty VirtualHardDisks | select -ExpandProperty HostVolume
                        $CanonicalName = (Get-Datastore -Name ($VMDisk).volumelabel | select -ExpandProperty ExtensionData).Info.vmfs.Extent.diskname
                        #$SectorSize = (Get-ScsiLun -CanonicalName $CanonicalName -VmHost $VMHost.name | select -ExpandProperty ExtensionData).capacity.BlockSize #I think it export data about logical block size
                        $ScsiDiskType = (Get-ScsiLun -CanonicalName $CanonicalName -VmHost $VMHost.name | select -ExpandProperty ExtensionData).ScsiDiskType
                        $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomSectorSize
                        if([string]::IsNullOrEmpty($ScsiDiskType)){
                            if(![string]::IsNullOrEmpty($Custom_Value)){
                                Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                if($?){$Change_VM = $true}
                            }
	                    }else{
                            #512n
	                        if($ScsiDiskType -eq "native512"){
		                        $SectorSize = "512n"
	                        }
	                        #512e
	                        elseif($ScsiDiskType -match "512"){
		                        $SectorSize = "512e"
	                        }
	                        #4kn
	                        elseif($ScsiDiskType -match "4"){
		                        $SectorSize = "4kn"
	                        }
                            if($Custom_Value.Value -ne $SectorSize){
                                Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomSectorSize -Value $SectorSize
                                if($?){$Change_VM = $true}
                            }
                        }
                        #Location
                        if([string]::IsNullOrEmpty($VM.Location)){
                            if(![string]::IsNullOrEmpty($Custom_Value)){
                                Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                if($?){$Change_VM = $true}
                            }
                        }else{
                            $DiskVolumes = $VMHost.DiskVolumes | select  name,Volumelabel
                            $DiskVolumes | %{
                                if($_.name.Split("\")[2] -eq $VM.Location.Split("\")[2]){
                                    if($Custom_Value.Value -ne $_.Volumelabel -and ![string]::IsNullOrEmpty($_.Volumelabel)){
                                        Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomLocation -Value $_.Volumelabel
                                        if($?){$Change_VM = $true}
                                    }
                                }
                            }
                        }
                        #VMCheckpoints
                        $VMCheckpoints=$VM.VMCheckpoints.count
                        $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomVMCheckpoints
                        if($VMCheckpoints -eq 0){
                            if(![string]::IsNullOrEmpty($Custom_Value)){
                                Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                if($?){$Change_VM = $true}
                            }
                        }else{
                            if($Custom_Value.Value -ne $VMCheckpoints){
                                Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomVMCheckpoints -Value $VMCheckpoints
                                if($?){$Change_VM = $true}
                            }
                        }
                        #Description
                        $VM.Description.split("`n") | foreach {
                            $description_to_custom = ""
                            if($_ -match "^ИС"){
                                $description_to_custom = $_ -replace "^ИС: ","";
                                $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_App
                                if([string]::IsNullOrEmpty($description_to_custom)){
                                    Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                    if($?){$Change_VM = $true}
                                }else{
                                    if($Custom_Value.Value -ne $description_to_custom){
                                        Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_App -Value $description_to_custom
                                        if($?){$Change_VM = $true}
                                    }
                                }
                            }elseif($_ -match "^Окружение"){
                                $description_to_custom = $_ -replace "^Окружение: ","";
                                $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_Env
                                if([string]::IsNullOrEmpty($description_to_custom)){
                                    #$Custom_Env_remove = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_Env
                                    Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                    if($?){$Change_VM = $true}
                                }else{
                                    if($Custom_Value.Value -ne $description_to_custom){
                                        Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_Env -Value $description_to_custom
                                        if($?){$Change_VM = $true}
                                    }
                                }
                            }elseif($_ -match "^Ответственный за ВМ"){
                                $description_to_custom = $_ -replace "^Ответственный за ВМ: ","";
                                $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_OwnerVM
                                if([string]::IsNullOrEmpty($description_to_custom)){
                                    #$Custom_OwnerVM_remove = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_OwnerVM
                                    Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                    if($?){$Change_VM = $true}
                                }else{
                                    if($Custom_Value.Value -ne $description_to_custom){
                                        Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_OwnerVM -Value $description_to_custom
                                        if($?){$Change_VM = $true}
                                    }
                                }
                            }elseif($_ -match "^Ответственный за ИС"){
                                $description_to_custom = $_ -replace "^Ответственный за ИС: ","";
                                $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_OwnerApp
                                if([string]::IsNullOrEmpty($description_to_custom)){
                                    #$Custom_OwnerApp_remove = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_OwnerApp
                                    Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                    if($?){$Change_VM = $true}
                                }else{
                                    if($Custom_Value.Value -ne $description_to_custom){
                                        Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_OwnerApp -Value $description_to_custom
                                        if($?){$Change_VM = $true}
                                    }
                                }
                            }elseif($_ -match "^Проект"){
                                $description_to_custom = $_ -replace "^Проект: ","";
                                $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_Project
                                if([string]::IsNullOrEmpty($description_to_custom)){
                                    #$Custom_Project_remove = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_Project
                                    Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                    if($?){$Change_VM = $true}
                                }else{
                                    if($Custom_Value.Value -ne $description_to_custom){
                                        Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_Project -Value $description_to_custom
                                        if($?){$Change_VM = $true}
                                    }
                                }
                            }elseif($_ -match "^Роль"){
                                $description_to_custom = $_ -replace "^Роль: ","";
                                $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_Role
                                if([string]::IsNullOrEmpty($description_to_custom)){
                                    #$Custom_Role_remove = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_Role
                                    Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                    if($?){$Change_VM = $true}
                                }else{
                                    if($Custom_Value.Value -ne $description_to_custom){
                                        Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $Custom_Role -Value $description_to_custom
                                        if($?){$Change_VM = $true}
                                    }
                                }
                            }
                        }
                        #Update VM
                        if($Change_VM){Refresh-VM -VM $VMName}
                    }
                    #disconnect from VMWar
                    #Disconnect-VIServer -Server $VMWareServer -Confirm: $false 
                    Disconnect-VIServer -Server $global:DefaultVIServers -Confirm: $false -Force
                }
            }
            $Children_Hash.Parent_Hash.finish_cycle++
        }).BeginInvoke()
        start-sleep -Seconds 5
}

while($Parent_Hash.finish_cycle -ne $Array_part_VMHosts.Count){
    Start-Sleep -Seconds 10
}