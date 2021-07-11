cls
#input data
$VMMServer = "server"
$VMWareServer = "server"
$n=0
# синхронизированная хэш-таблица Hyper-V
$HyperV_Hash = [HashTable]::Synchronized(@{ Number_Hosts=$Number_Hosts;Array_part_VMHosts = $Array_part_VMHosts; VMMServer = $VMMServer; VMWareServer = $VMWareServer })
$HyperV_Runspace = [RunSpaceFactory]::CreateRunspace()
$HyperV_Runspace.ApartmentState = "STA"
$HyperV_Runspace.ThreadOptions = "ReuseThread"
$HyperV_Runspace.Open()
$HyperV_Runspace.SessionStateProxy.setVariable("HyperV_Hash", $HyperV_Hash)
$HyperV_PowerShell = [PowerShell]::Create()
$HyperV_PowerShell.Runspace = $HyperV_Runspace
$HyperV_PowerShell.AddScript({   
	while ($true) {
        $HyperV_Hash.Array_part_VMHosts = @()
        $VMHosts = Get-SCVMHost -VMMServer $HyperV_Hash.VMMServer | where { $_.VirtualizationPlatform -like "HyperV" } | select Name,VirtualizationPlatform,DiskVolumes  | Sort-Object VirtualizationPlatform,name
        for($i=0; $i -lt $VMHosts.Count; $i+=3){ 
            $HyperV_Hash.Array_part_VMHosts += ,@($VMHosts[$i..($i+2)]);
        }
        $HyperV_Hash.Number_Hosts = $HyperV_Hash.Array_part_VMHosts.count
        start-sleep -Seconds 15
    }
}).BeginInvoke()

#all queries
while($true){
    if($HyperV_Hash.Array_part_VMHosts[$n] -and $HyperV_Hash.Number_Hosts -eq $Number_Hosts_eq){
        # синхронизированная хэш-таблица
        $H_Hash = [HashTable]::Synchronized(@{ Number_Hosts_eq=$Number_Hosts_eq;number = $n; HyperV_Hash = $HyperV_Hash; VMMServer = $VMMServer; VMWareServer = $VMWareServer})
        $H_Runspace = [RunSpaceFactory]::CreateRunspace()
        $H_Runspace.ApartmentState = "STA"
        $H_Runspace.ThreadOptions = "ReuseThread"
        $H_Runspace.Open()
        $H_Runspace.SessionStateProxy.setVariable("H_Hash", $H_Hash)
        $H_PowerShell = [PowerShell]::Create()
        $H_PowerShell.Runspace = $H_Runspace
        $H_PowerShell.AddScript({
            #input
            $Gold = "Gold"
            $Silver = "Silver"
            $Bronze = "Bronze"
            $Gold_size = 15000
            $Silver_size = 10000
            $Bronze_size = 5000
            $MS = 200000
            $PolicyIOPS_MaximumIOPS=0 #policy IOPS value
            #input SQL
            $SQLServer = "server"
            $SQLDBName = "DB"
            $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
            $SqlConnection.ConnectionString = "Server = $SQLServer; Database = $SQLDBName; Integrated Security=True"
            #email
            Function email {
                param([string] $FunctionVMname,
                [int] $FunctionAverageLatency,
                [int] $FunctionAverageIOPS,
                [int] $FunctionMaximumIOPS,
                [string] $FunctionPolicyIOPS,
                [string] $FunctionLocation,
                [string] $FunctionMeteringDuration,
                [int] $FunctionMS,
                [string] $FunctionIS)
                $FunctionMS_minutes = $FunctionMS/1000/60
                $FunctionAverageLatency_minutes = $FunctionAverageLatency/1000/60
                $smtp = "SMTP_server"
                $from = "vmm@mail.ru"
	            $to = "username@mail.ru"
                $subject = "Состояние ВМ: "+$FunctionVMname + " -> Location: " + $FunctionLocation
                [string]$body = ""
                $body += "Наблюдается превышение задержки >"+$FunctionMS+" MS ("+[math]::round($FunctionMS_minutes,2)+" minutes)."
                $body += "`nAverageLatency - " + $FunctionAverageLatency+" MS ("+[math]::round($FunctionAverageLatency_minutes,2)+" minutes)."
                $body += "`nAverageIOPS - " + $FunctionAverageIOPS+" IOPS."
                $body += "`nMaximumIOPS - " + $FunctionMaximumIOPS+" IOPS."
                $body += "`nPolicyIOPS - " + $FunctionPolicyIOPS+"."
                $body += "`nMeteringDuration - " + $FunctionMeteringDuration+"."
                $body += "`nLocation - " + $FunctionLocation+"."
                $body += "`nИС - " + $FunctionIS+"."
	            send-MailMessage -SmtpServer $smtp -To $to -From $from -Subject $subject -Body $body -Encoding unicode -Priority High
            }
            #Custom VMM
            $CustomUptime = Get-SCCustomProperty -VMMServer $H_Hash.VMMServer -Name "Uptime"
            $CustomUptimeHost = Get-SCCustomProperty -VMMServer $H_Hash.VMMServer -Name "Uptime on the Host"
            $CustomLastSuccessfulBackupTime = Get-SCCustomProperty -VMMServer $H_Hash.VMMServer -Name "LastSuccessfulBackupTime"
            $CustomAverageIOPS = Get-SCCustomProperty -VMMServer $H_Hash.VMMServer -Name "AverageIOPS"
            $CustomAverageLatency = Get-SCCustomProperty -VMMServer $H_Hash.VMMServer -Name "AverageLatency"
            $CustomDynamicStatus = Get-SCCustomProperty -VMMServer $H_Hash.VMMServer -Name "CustomDynamicStatus"
            $CustomMaximumIOPS = Get-SCCustomProperty -VMMServer $H_Hash.VMMServer -Name "MaximumIOPS"
            $CustomPolicyIOPS = Get-SCCustomProperty -VMMServer $H_Hash.VMMServer -Name "PolicyIOPS"
            $CustomMeteringDuration = Get-SCCustomProperty -VMMServer $H_Hash.VMMServer -Name "MeteringDuration"
            #Custom SQL
            $SqlQuery = "SELECT * FROM VirtualManagerDB.dbo.tbl_BTBS_CustomProperty"
            $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
            $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
            $SqlAdapter.SelectCommand = $SqlCmd
            $DataSet = New-Object System.Data.DataSet
            $SqlAdapter.Fill($DataSet)
            $CustomUptime_ID = ($DataSet.Tables[0] | ?{$_.name -eq "Uptime"} | select -ExpandProperty ID).guid
            $CustomUptimeHost_ID = ($DataSet.Tables[0] | ?{$_.name -eq "Uptime on the Host"} | select -ExpandProperty ID).guid
            $CustomLastSuccessfulBackupTime_ID = ($DataSet.Tables[0] | ?{$_.name -eq "LastSuccessfulBackupTime"} | select -ExpandProperty ID).guid
            $CustomAverageIOPS_ID = ($DataSet.Tables[0] | ?{$_.name -eq "AverageIOPS"} | select -ExpandProperty ID).guid
            $CustomAverageLatency_ID = ($DataSet.Tables[0] | ?{$_.name -eq "AverageLatency"} | select -ExpandProperty ID).guid
            $CustomDynamicStatus_ID = ($DataSet.Tables[0] | ?{$_.name -eq "CustomDynamicStatus"} | select -ExpandProperty ID).guid
            $CustomMaximumIOPS_ID = ($DataSet.Tables[0] | ?{$_.name -eq "MaximumIOPS"} | select -ExpandProperty ID).guid
            $CustomPolicyIOPS_ID = ($DataSet.Tables[0] | ?{$_.name -eq "PolicyIOPS"} | select -ExpandProperty ID).guid
            $CustomMeteringDuration_ID = ($DataSet.Tables[0] | ?{$_.name -eq "MeteringDuration"} | select -ExpandProperty ID).guid
            #-----------------------------------------------------------------------------
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
            $Order_number_in_hash = $H_Hash.number
            while ($H_Hash.HyperV_Hash.Number_Hosts -eq $H_Hash.Number_Hosts_eq) {
                    foreach ( $VMHost in $H_Hash.HyperV_Hash.Array_part_VMHosts[$Order_number_in_hash] ) {
                        if($VMHost.VirtualizationPlatform -eq "HyperV"){
                            $VMs = Get-SCVirtualMachine -VMMServer $H_Hash.VMMserver -VMHost $VMHost.name | Sort-Object name
                            foreach ( $VM in $VMs ) {
                                $MaximumIOPS = 0
                                $Change_VM = $false
                                $VMname = $VM.name
                                $VM_ID = $VM.ID.guid
                                #CustomUptime_Value
                                    $SqlQuery = "
	                                    SELECT * FROM VirtualManagerDB.dbo.tbl_BTBS_CustomPropertyValue
                                        WHERE tbl_BTBS_CustomPropertyValue.ObjectID = '$($VM_ID)' AND tbl_BTBS_CustomPropertyValue.CustomPropertyID = '$($CustomUptime_ID)';
                                    "
                                    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
                                    $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                                    $SqlAdapter.SelectCommand = $SqlCmd
                                    $DataSet = New-Object System.Data.DataSet
                                    $SqlAdapter.Fill($DataSet)
                                    $CustomUptime_Value = $DataSet.Tables[0].Value
                                #CustomUptimeHost_Value
                                    $SqlQuery = "
	                                    SELECT * FROM VirtualManagerDB.dbo.tbl_BTBS_CustomPropertyValue
                                        WHERE tbl_BTBS_CustomPropertyValue.ObjectID = '$($VM_ID)' AND tbl_BTBS_CustomPropertyValue.CustomPropertyID = '$($CustomUptimeHost_ID)';
                                    "
                                    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
                                    $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                                    $SqlAdapter.SelectCommand = $SqlCmd
                                    $DataSet = New-Object System.Data.DataSet
                                    $SqlAdapter.Fill($DataSet)
                                    $CustomUptimeHost_Value = $DataSet.Tables[0].Value
                                #CustomPolicyIOPS_Value
                                    $SqlQuery = "
	                                    SELECT * FROM VirtualManagerDB.dbo.tbl_BTBS_CustomPropertyValue
                                        WHERE tbl_BTBS_CustomPropertyValue.ObjectID = '$($VM_ID)' AND tbl_BTBS_CustomPropertyValue.CustomPropertyID = '$($CustomPolicyIOPS_ID)';
                                    "
                                    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
                                    $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                                    $SqlAdapter.SelectCommand = $SqlCmd
                                    $DataSet = New-Object System.Data.DataSet
                                    $SqlAdapter.Fill($DataSet)
                                    $CustomPolicyIOPS_Value = $DataSet.Tables[0].Value
                                #CustomMaximumIOPS_Value
                                    $SqlQuery = "
	                                    SELECT * FROM VirtualManagerDB.dbo.tbl_BTBS_CustomPropertyValue
                                        WHERE tbl_BTBS_CustomPropertyValue.ObjectID = '$($VM_ID)' AND tbl_BTBS_CustomPropertyValue.CustomPropertyID = '$($CustomMaximumIOPS_ID)';
                                    "
                                    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
                                    $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                                    $SqlAdapter.SelectCommand = $SqlCmd
                                    $DataSet = New-Object System.Data.DataSet
                                    $SqlAdapter.Fill($DataSet)
                                    $CustomMaximumIOPS_Value = $DataSet.Tables[0].Value
                                #CustomLastSuccessfulBackupTime_Value
                                    $SqlQuery = "
	                                    SELECT * FROM VirtualManagerDB.dbo.tbl_BTBS_CustomPropertyValue
                                        WHERE tbl_BTBS_CustomPropertyValue.ObjectID = '$($VM_ID)' AND tbl_BTBS_CustomPropertyValue.CustomPropertyID = '$($CustomLastSuccessfulBackupTime_ID)';
                                    "
                                    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
                                    $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                                    $SqlAdapter.SelectCommand = $SqlCmd
                                    $DataSet = New-Object System.Data.DataSet
                                    $SqlAdapter.Fill($DataSet)
                                    $CustomLastSuccessfulBackupTime_Value = $DataSet.Tables[0].Value
                                #CustomMeteringDuration_Value
                                    $SqlQuery = "
	                                    SELECT * FROM VirtualManagerDB.dbo.tbl_BTBS_CustomPropertyValue
                                        WHERE tbl_BTBS_CustomPropertyValue.ObjectID = '$($VM_ID)' AND tbl_BTBS_CustomPropertyValue.CustomPropertyID = '$($CustomMeteringDuration_ID)';
                                    "
                                    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
                                    $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                                    $SqlAdapter.SelectCommand = $SqlCmd
                                    $DataSet = New-Object System.Data.DataSet
                                    $SqlAdapter.Fill($DataSet)
                                    $CustomMeteringDuration_Value = $DataSet.Tables[0].Value
                                #CustomAverageIOPS_Value
                                    $SqlQuery = "
	                                    SELECT * FROM VirtualManagerDB.dbo.tbl_BTBS_CustomPropertyValue
                                        WHERE tbl_BTBS_CustomPropertyValue.ObjectID = '$($VM_ID)' AND tbl_BTBS_CustomPropertyValue.CustomPropertyID = '$($CustomAverageIOPS_ID)';
                                    "
                                    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
                                    $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                                    $SqlAdapter.SelectCommand = $SqlCmd
                                    $DataSet = New-Object System.Data.DataSet
                                    $SqlAdapter.Fill($DataSet)
                                    $CustomAverageIOPS_Value = $DataSet.Tables[0].Value
                                #CustomAverageLatency_Value
                                    $SqlQuery = "
	                                    SELECT * FROM VirtualManagerDB.dbo.tbl_BTBS_CustomPropertyValue
                                        WHERE tbl_BTBS_CustomPropertyValue.ObjectID = '$($VM_ID)' AND tbl_BTBS_CustomPropertyValue.CustomPropertyID = '$($CustomAverageLatency_ID)';
                                    "
                                    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
                                    $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                                    $SqlAdapter.SelectCommand = $SqlCmd
                                    $DataSet = New-Object System.Data.DataSet
                                    $SqlAdapter.Fill($DataSet)
                                    $CustomAverageLatency_Value = $DataSet.Tables[0].Value
                                #MeasureVM
                                    if(Get-VM -ComputerName $VMHost.name -Name $VMname | select -ExpandProperty ResourceMeteringEnabled){
                                        $MeasureVM = Measure-VM -ComputerName $VMHost.name -Name $VMname | Select-Object HardDiskMetrics,AggregatedAverageNormalizedIOPS,AggregatedAverageLatency,MeteringDuration
                                        if($?){
                                            $MeasureVM.HardDiskMetrics | %{$MaximumIOPS += $_.VirtualHardDisk.MaximumIOPS}
                                        }else{
                                            Disable-VMResourceMetering -ComputerName $VMHost.name -VMName $VMname
                                            Enable-VMResourceMetering -ComputerName $VMHost.name -VMName $VMname
                                            $MeasureVM = Measure-VM -ComputerName $VMHost.name -Name $VMname | Select-Object HardDiskMetrics,AggregatedAverageNormalizedIOPS,AggregatedAverageLatency,MeteringDuration
                                            $MeasureVM.HardDiskMetrics | %{$MaximumIOPS += $_.VirtualHardDisk.MaximumIOPS}
                                        }
                                    }else{
                                        Enable-VMResourceMetering -ComputerName $VMHost.name -VMName $VMname
                                        $MeasureVM = Measure-VM -ComputerName $VMHost.name -Name $VMname | Select-Object HardDiskMetrics,AggregatedAverageNormalizedIOPS,AggregatedAverageLatency,MeteringDuration
                                        $MeasureVM.HardDiskMetrics | %{$MaximumIOPS += $_.VirtualHardDisk.MaximumIOPS}
                                    }
                                #MaximumIOPS
                                    if($CustomPolicyIOPS_Value -eq $Gold){
                                        $PolicyIOPS_MaximumIOPS = $MeasureVM.HardDiskMetrics.Count*$Gold_Size
                                    }elseif($CustomPolicyIOPS_Value -eq $Silver){
                                        $PolicyIOPS_MaximumIOPS = $MeasureVM.HardDiskMetrics.Count*$Silver_Size
                                    }elseif($CustomPolicyIOPS_Value -eq $Bronze){
                                        $PolicyIOPS_MaximumIOPS = $MeasureVM.HardDiskMetrics.Count*$Bronze_Size
                                    }
                                #if($VM.VirtualMachineState -eq "Running"){
                                if($VM.StatusString -eq "Running"){
                                    #AggregatedAverageNormalizedIOPS
                                        if(![string]::IsNullOrEmpty($CustomAverageIOPS_Value) -and ![string]::IsNullOrEmpty($MeasureVM.AggregatedAverageNormalizedIOPS)){
                                            if($CustomAverageIOPS_Value -ne $MeasureVM.AggregatedAverageNormalizedIOPS){
                                                $SqlQuery = "
                                                    UPDATE dbo.[tbl_BTBS_CustomPropertyValue]
                                                    SET [Value] = '$($MeasureVM.AggregatedAverageNormalizedIOPS)'
                                                    WHERE tbl_BTBS_CustomPropertyValue.ObjectID = '$($VM_ID)' AND tbl_BTBS_CustomPropertyValue.CustomPropertyID = '$($CustomAverageIOPS_ID)';
                                                "
                                                $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
                                                $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                                                $SqlAdapter.SelectCommand = $SqlCmd
                                                $DataSet = New-Object System.Data.DataSet
                                                $SqlAdapter.Fill($DataSet)
                                                if($?){$Change_VM = $true}
                                            }
                                        }elseif($CustomAverageIOPS_Value -ne $MeasureVM.AggregatedAverageNormalizedIOPS -and ![string]::IsNullOrEmpty($MeasureVM.AggregatedAverageNormalizedIOPS)){
                                            Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomAverageIOPS -Value $MeasureVM.AggregatedAverageNormalizedIOPS
                                            if($?){$Change_VM = $true}
                                        }elseif(![string]::IsNullOrEmpty($CustomAverageIOPS_Value)){ #Remove
                                            $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomAverageIOPS
                                            Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                            if($?){$Change_VM = $true}
                                        }
                                    #AggregatedAverageLatency
                                        if(![string]::IsNullOrEmpty($CustomAverageLatency_Value) -and ![string]::IsNullOrEmpty($MeasureVM.AggregatedAverageLatency) ){
                                            if($CustomAverageLatency_Value -ne $MeasureVM.AggregatedAverageLatency){
                                                $SqlQuery = "
                                                    UPDATE dbo.[tbl_BTBS_CustomPropertyValue]
                                                    SET [Value] = '$($MeasureVM.AggregatedAverageLatency)'
                                                    WHERE tbl_BTBS_CustomPropertyValue.ObjectID = '$($VM_ID)' AND tbl_BTBS_CustomPropertyValue.CustomPropertyID = '$($CustomAverageLatency_ID)';
                                                "
                                                $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
                                                $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                                                $SqlAdapter.SelectCommand = $SqlCmd
                                                $DataSet = New-Object System.Data.DataSet
                                                $SqlAdapter.Fill($DataSet)
                                                if($?){$Change_VM = $true}
                                            }
                                        }elseif($CustomAverageLatency_Value -ne $MeasureVM.AggregatedAverageLatency -and ![string]::IsNullOrEmpty($MeasureVM.AggregatedAverageLatency)){
                                            Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomAverageLatency -Value $MeasureVM.AggregatedAverageLatency
                                            if($?){$Change_VM = $true}
                                        }elseif(![string]::IsNullOrEmpty($CustomAverageLatency_Value)){ #Remove
                                            $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomAverageLatency
                                            Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                            if($?){$Change_VM = $true}
                                        }
                                    #MeteringDuration
                                        if([string]::IsNullOrEmpty($MeasureVM.MeteringDuration)){
                                            Reset-VMResourceMetering -ComputerName $VMHost.name -VMName $VMname
                                            $MeasureVM = Measure-VM -ComputerName $VMHost.name -Name $VMname | Select-Object HardDiskMetrics,AggregatedAverageNormalizedIOPS,AggregatedAverageLatency,MeteringDuration
                                        }
                                        if(![string]::IsNullOrEmpty($CustomMeteringDuration_Value) -and ![string]::IsNullOrEmpty($MeasureVM.MeteringDuration)){ #SQL
                                            if($CustomMeteringDuration_Value -ne $MeasureVM.MeteringDuration){
                                                $SqlQuery = "
                                                    UPDATE dbo.[tbl_BTBS_CustomPropertyValue]
                                                    SET [Value] = '$($MeasureVM.MeteringDuration)'
                                                    WHERE tbl_BTBS_CustomPropertyValue.ObjectID = '$($VM_ID)' AND tbl_BTBS_CustomPropertyValue.CustomPropertyID = '$($CustomMeteringDuration_ID)';
                                                "
                                                $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
                                                $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                                                $SqlAdapter.SelectCommand = $SqlCmd
                                                $DataSet = New-Object System.Data.DataSet
                                                $SqlAdapter.Fill($DataSet)
                                                if($?){$Change_VM = $true}
                                            }
                                        }elseif(![string]::IsNullOrEmpty($MeasureVM.MeteringDuration) -and $CustomMeteringDuration_Value -ne $MeasureVM.MeteringDuration){ #VMM
                                            Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomMeteringDuration -Value $MeasureVM.MeteringDuration
                                            if($?){$Change_VM = $true}
                                        }elseif(![string]::IsNullOrEmpty($CustomMeteringDuration_Value)){ #Remove
                                            $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomMeteringDuration
                                            Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                            if($?){$Change_VM = $true}
                                        }
                                    #PolicyIOPS and MaximumIOPS
                                        if(![string]::IsNullOrEmpty($CustomMaximumIOPS_Value) -and ![string]::IsNullOrEmpty($MaximumIOPS)){ #SQL
                                            if($CustomPolicyIOPS_Value -eq $Gold -and $PolicyIOPS_MaximumIOPS -ne $MaximumIOPS){
                                                $MeasureVM.HardDiskMetrics | %{
                                                    Set-VMHardDiskDrive -ComputerName $VMHost.name -VMName $VMname -ControllerType $_.VirtualHardDisk.ControllerType `
                                                    -ControllerNumber $_.VirtualHardDisk.ControllerNumber -ControllerLocation $_.VirtualHardDisk.ControllerLocation -MaximumIOPS $Gold_size
                                                    if($?){$Change_VM = $true}
                                                }
                                                $SqlQuery = "
                                                    UPDATE dbo.[tbl_BTBS_CustomPropertyValue]
                                                    SET [Value] = '$($PolicyIOPS_MaximumIOPS)'
                                                    WHERE tbl_BTBS_CustomPropertyValue.ObjectID = '$($VM_ID)' AND tbl_BTBS_CustomPropertyValue.CustomPropertyID = '$($CustomMaximumIOPS_ID)';
                                                "
                                                $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
                                                $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                                                $SqlAdapter.SelectCommand = $SqlCmd
                                                $DataSet = New-Object System.Data.DataSet
                                                $SqlAdapter.Fill($DataSet)
                                                if($?){$Change_VM = $true}
                                            }elseif($CustomPolicyIOPS_Value -eq $Silver -and $PolicyIOPS_MaximumIOPS -ne $MaximumIOPS){
                                                $MeasureVM.HardDiskMetrics | %{
                                                    Set-VMHardDiskDrive -ComputerName $VMHost.name -VMName $VMname -ControllerType $_.VirtualHardDisk.ControllerType `
                                                    -ControllerNumber $_.VirtualHardDisk.ControllerNumber -ControllerLocation $_.VirtualHardDisk.ControllerLocation -MaximumIOPS $Silver_size
                                                    if($?){$Change_VM = $true}
                                                }
                                                $SqlQuery = "
                                                    UPDATE dbo.[tbl_BTBS_CustomPropertyValue]
                                                    SET [Value] = '$($PolicyIOPS_MaximumIOPS)'
                                                    WHERE tbl_BTBS_CustomPropertyValue.ObjectID = '$($VM_ID)' AND tbl_BTBS_CustomPropertyValue.CustomPropertyID = '$($CustomMaximumIOPS_ID)';
                                                "
                                                $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
                                                $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                                                $SqlAdapter.SelectCommand = $SqlCmd
                                                $DataSet = New-Object System.Data.DataSet
                                                $SqlAdapter.Fill($DataSet)
                                                if($?){$Change_VM = $true}
                                            }elseif($CustomPolicyIOPS_Value -eq $Bronze -and $PolicyIOPS_MaximumIOPS -ne $MaximumIOPS){
                                                $MeasureVM.HardDiskMetrics | %{
                                                    Set-VMHardDiskDrive -ComputerName $VMHost.name -VMName $VMname -ControllerType $_.VirtualHardDisk.ControllerType `
                                                    -ControllerNumber $_.VirtualHardDisk.ControllerNumber -ControllerLocation $_.VirtualHardDisk.ControllerLocation -MaximumIOPS $Bronze_size
                                                    if($?){$Change_VM = $true}
                                                }
                                                $SqlQuery = "
                                                    UPDATE dbo.[tbl_BTBS_CustomPropertyValue]
                                                    SET [Value] = '$($PolicyIOPS_MaximumIOPS)'
                                                    WHERE tbl_BTBS_CustomPropertyValue.ObjectID = '$($VM_ID)' AND tbl_BTBS_CustomPropertyValue.CustomPropertyID = '$($CustomMaximumIOPS_ID)';
                                                "
                                                $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
                                                $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                                                $SqlAdapter.SelectCommand = $SqlCmd
                                                $DataSet = New-Object System.Data.DataSet
                                                $SqlAdapter.Fill($DataSet)
                                                if($?){$Change_VM = $true}
                                            }elseif([string]::IsNullOrEmpty($CustomPolicyIOPS_Value) -and $PolicyIOPS_MaximumIOPS -ne $MaximumIOPS -and $MaximumIOPS -ne 0){
                                                $SqlQuery = "
                                                    UPDATE dbo.[tbl_BTBS_CustomPropertyValue]
                                                    SET [Value] = '$($MaximumIOPS)'
                                                    WHERE tbl_BTBS_CustomPropertyValue.ObjectID = '$($VM_ID)' AND tbl_BTBS_CustomPropertyValue.CustomPropertyID = '$($CustomMaximumIOPS_ID)';
                                                "
                                                $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
                                                $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                                                $SqlAdapter.SelectCommand = $SqlCmd
                                                $DataSet = New-Object System.Data.DataSet
                                                $SqlAdapter.Fill($DataSet)
                                                if($?){$Change_VM = $true}
                                            }elseif([string]::IsNullOrEmpty($CustomPolicyIOPS_Value) -and $MaximumIOPS -eq 0){
                                                $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomMaximumIOPS
                                                Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                                if($?){$Change_VM = $true}
                                            }
                                            <# Shvarev
                                            elseif([string]::IsNullOrEmpty($CustomPolicyIOPS_Value) -and ![string]::IsNullOrEmpty($CustomMaximumIOPS_Value)){
                                                $MeasureVM.HardDiskMetrics | %{
                                                    Set-VMHardDiskDrive -ComputerName $VMHost.name -VMName $VMname -ControllerType $_.VirtualHardDisk.ControllerType `
                                                    -ControllerNumber $_.VirtualHardDisk.ControllerNumber -ControllerLocation $_.VirtualHardDisk.ControllerLocation -MaximumIOPS 0
                                                    if($?){$Change_VM = $true}
                                                }
                                                $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomMaximumIOPS
                                                Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                                if($?){$Change_VM = $true}
                                            }#>
                                        }elseif(![string]::IsNullOrEmpty($MaximumIOPS)){ #VMM
                                            if($CustomPolicyIOPS_Value -eq $Gold -and $PolicyIOPS_MaximumIOPS -ne $MaximumIOPS){
                                                $MeasureVM.HardDiskMetrics | %{
                                                    Set-VMHardDiskDrive -ComputerName $VMHost.name -VMName $VMname -ControllerType $_.VirtualHardDisk.ControllerType `
                                                    -ControllerNumber $_.VirtualHardDisk.ControllerNumber -ControllerLocation $_.VirtualHardDisk.ControllerLocation -MaximumIOPS $Gold_size
                                                    if($?){$Change_VM = $true}
                                                }
                                                Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomMaximumIOPS -Value $PolicyIOPS_MaximumIOPS
                                                if($?){$Change_VM = $true}
                                            }elseif($CustomPolicyIOPS_Value -eq $Silver -and $PolicyIOPS_MaximumIOPS -ne $MaximumIOPS){
                                                $MeasureVM.HardDiskMetrics | %{
                                                    Set-VMHardDiskDrive -ComputerName $VMHost.name -VMName $VMname -ControllerType $_.VirtualHardDisk.ControllerType `
                                                    -ControllerNumber $_.VirtualHardDisk.ControllerNumber -ControllerLocation $_.VirtualHardDisk.ControllerLocation -MaximumIOPS $Silver_size
                                                    if($?){$Change_VM = $true}
                                                }
                                                Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomMaximumIOPS -Value $PolicyIOPS_MaximumIOPS
                                                if($?){$Change_VM = $true}
                                            }elseif($CustomPolicyIOPS_Value -eq $Bronze -and $PolicyIOPS_MaximumIOPS -ne $MaximumIOPS){
                                                $MeasureVM.HardDiskMetrics | %{
                                                    Set-VMHardDiskDrive -ComputerName $VMHost.name -VMName $VMname -ControllerType $_.VirtualHardDisk.ControllerType `
                                                    -ControllerNumber $_.VirtualHardDisk.ControllerNumber -ControllerLocation $_.VirtualHardDisk.ControllerLocation -MaximumIOPS $Bronze_size
                                                    if($?){$Change_VM = $true}
                                                }
                                                Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomMaximumIOPS -Value $PolicyIOPS_MaximumIOPS
                                                if($?){$Change_VM = $true}
                                            }elseif([string]::IsNullOrEmpty($CustomPolicyIOPS_Value) -and $PolicyIOPS_MaximumIOPS -ne $MaximumIOPS -and $MaximumIOPS -ne 0){
                                                Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomMaximumIOPS -Value $MaximumIOPS
                                                if($?){$Change_VM = $true}
                                            }elseif([string]::IsNullOrEmpty($CustomPolicyIOPS_Value) -and $MaximumIOPS -eq 0){
                                                $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomMaximumIOPS
                                                Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                                if($?){$Change_VM = $true}
                                            }
                                            <#elseif([string]::IsNullOrEmpty($CustomPolicyIOPS_Value) -and ![string]::IsNullOrEmpty($CustomMaximumIOPS_Value)){
                                                $MeasureVM.HardDiskMetrics | %{
                                                    Set-VMHardDiskDrive -ComputerName $VMHost.name -VMName $VMname -ControllerType $_.VirtualHardDisk.ControllerType `
                                                    -ControllerNumber $_.VirtualHardDisk.ControllerNumber -ControllerLocation $_.VirtualHardDisk.ControllerLocation -MaximumIOPS 0
                                                    if($?){$Change_VM = $true}
                                                }
                                                Remove-SCCustomPropertyValue -CustomPropertyValue $CustomMaximumIOPS_Value
                                                if($?){$Change_VM = $true}
                                            }#>
                                        }elseif(![string]::IsNullOrEmpty($CustomMaximumIOPS_Value)){ #Remove
                                            $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomMaximumIOPS
                                            Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                            if($?){$Change_VM = $true}
                                        }
                                    #KVP Uptime
                                        $VMConf = Get-WmiObject -ComputerName $VMHost.name -Namespace "root\virtualization\v2" -Query "SELECT * FROM Msvm_ComputerSystem WHERE ElementName like '$VMName' "
                                        $KVPData = Get-WmiObject -ComputerName $VMHost.name -Namespace "root\virtualization\v2" -Query "Associators of {$VMConf} Where AssocClass=Msvm_SystemDevice ResultClass=Msvm_KvpExchangeComponent"
                                        $Uptime = $KVPData.GuestExchangeItems | Import-CimXml | select name,data | where {$_.name -eq "Uptime"}
                                        if([string]::IsNullOrEmpty($Uptime)){
                                            if(![string]::IsNullOrEmpty($CustomUptime_Value)){
                                                $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomUptime
                                                Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                                if($?){$Change_VM = $true}
                                            }
	                                    }else{
                                            $Uptime = GetUpTime($Uptime.data)
                                            if(![string]::IsNullOrEmpty($Uptime) -and ![string]::IsNullOrEmpty($CustomUptime_Value) -and $CustomUptime_Value -ne $Uptime){
                                                $SqlQuery = "
                                                    UPDATE dbo.[tbl_BTBS_CustomPropertyValue]
                                                    SET [Value] = '$($Uptime)'
                                                    WHERE tbl_BTBS_CustomPropertyValue.ObjectID = '$($VM_ID)' AND tbl_BTBS_CustomPropertyValue.CustomPropertyID = '$($CustomUptime_ID)';
                                                "
                                                $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
                                                $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                                                $SqlAdapter.SelectCommand = $SqlCmd
                                                $DataSet = New-Object System.Data.DataSet
                                                $SqlAdapter.Fill($DataSet)
                                                if($?){$Change_VM = $true}
                                            }elseif($Custom_Value -ne $Uptime -and ![string]::IsNullOrEmpty($Uptime) ){
	                                            Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomUptime -Value $Uptime
                                                if($?){$Change_VM = $true}
                                            }elseif(![string]::IsNullOrEmpty($CustomUptime_Value)){
                                                $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomUptime
                                                Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                                if($?){$Change_VM = $true}
                                            }
	                                    }
                                    #Uptime on the Host
                                        $Uptime_Host = get-vm -ComputerName $VMHost.name -Name $VMName | select -ExpandProperty Uptime
                                        if(![string]::IsNullOrEmpty($Uptime_Host) -and ![string]::IsNullOrEmpty($CustomUptimeHost_Value) -and $CustomUptimeHost_Value -ne $Uptime_Host){ #SQL
                                            $Uptime_Host = "$($Uptime_Host.Days).$($Uptime_Host.Hours):$($Uptime_Host.Minutes):$($Uptime_Host.Seconds)"
                                            $SqlQuery = "
                                                UPDATE dbo.[tbl_BTBS_CustomPropertyValue]
                                                SET [Value] = '$($Uptime_Host)'
                                                WHERE tbl_BTBS_CustomPropertyValue.ObjectID = '$($VM_ID)' AND tbl_BTBS_CustomPropertyValue.CustomPropertyID = '$($CustomUptimeHost_ID)';
                                            "
                                            $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
                                            $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                                            $SqlAdapter.SelectCommand = $SqlCmd
                                            $DataSet = New-Object System.Data.DataSet
                                            $SqlAdapter.Fill($DataSet)
                                            if($?){$Change_VM = $true}
                                        }elseif(![string]::IsNullOrEmpty($Uptime_Host) -and $CustomUptimeHost_Value -ne $Uptime_Host){ #VMM
                                            $Uptime_Host = "$($Uptime_Host.Days).$($Uptime_Host.Hours):$($Uptime_Host.Minutes):$($Uptime_Host.Seconds)"
                                            Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomUptimeHost -Value $Uptime_Host
                                            if($?){$Change_VM = $true}
                                        }elseif(![string]::IsNullOrEmpty($CustomUptimeHost_Value)){
                                            $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomUptimeHost
                                            Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                            if($?){$Change_VM = $true}
                                        }
                                    #------------------------------------------------------------------
                                    #LastSuccessfulBackupTime
                                        $VMConf = Get-WmiObject -ComputerName $VMHost.name -Namespace "root\virtualization\v2" -Query "SELECT * FROM Msvm_ComputerSystem WHERE ElementName like '$VMName' AND caption like 'Virtual%' "
                                        if([string]::IsNullOrEmpty($VMConf.LastSuccessfulBackupTime)){
                                            if(![string]::IsNullOrEmpty($CustomLastSuccessfulBackupTime_Value)){
                                                $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomLastSuccessfulBackupTime
                                                Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                                if($?){$Change_VM = $true}
                                            }
                                        }else{
                                            $TimeStamp = $VMConf.LastSuccessfulBackupTime -replace "[.].*$",""
                                            $LastSuccessfulBackupTime = $TimeStamp -replace '^(....)(..)(..)(..)(..)(..)$','$1.$2.$3 $4:$5:$6'
                                            if(![string]::IsNullOrEmpty($LastSuccessfulBackupTime) -and ![string]::IsNullOrEmpty($CustomLastSuccessfulBackupTime_Value) -and $CustomLastSuccessfulBackupTime_Value -ne $LastSuccessfulBackupTime){
                                                $SqlQuery = "
                                                    UPDATE dbo.[tbl_BTBS_CustomPropertyValue]
                                                    SET [Value] = '$($LastSuccessfulBackupTime)'
                                                    WHERE tbl_BTBS_CustomPropertyValue.ObjectID = '$($VM_ID)' AND tbl_BTBS_CustomPropertyValue.CustomPropertyID = '$($CustomLastSuccessfulBackupTime_ID)';
                                                "
                                                $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
                                                $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                                                $SqlAdapter.SelectCommand = $SqlCmd
                                                $DataSet = New-Object System.Data.DataSet
                                                $SqlAdapter.Fill($DataSet)
                                                if($?){$Change_VM = $true}
                                            }elseif(![string]::IsNullOrEmpty($LastSuccessfulBackupTime) -and $CustomLastSuccessfulBackupTime_Value -ne $LastSuccessfulBackupTime){
                                                Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomLastSuccessfulBackupTime -Value $LastSuccessfulBackupTime
                                                if($?){$Change_VM = $true}
                                            }
                                        }
                                }else{
                                    if(![string]::IsNullOrEmpty($CustomUptime_Value)){
                                        $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomUptime
                                        Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                        if($?){$Change_VM = $true}
                                    }
                                    if(![string]::IsNullOrEmpty($CustomUptimeHost_Value)){
                                        $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomUptimeHost
                                        Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                        if($?){$Change_VM = $true}
                                    }
                                    if(![string]::IsNullOrEmpty($CustomAverageIOPS_Value)){
                                        $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomAverageIOPS
                                        Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                        if($?){$Change_VM = $true}
                                    }
                                    if(![string]::IsNullOrEmpty($CustomAverageLatency_Value)){
                                        $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomAverageLatency
                                        Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                        if($?){$Change_VM = $true}
                                    }
                                    #PolicyIOPS and MaximumIOPS
                                        if(![string]::IsNullOrEmpty($CustomMaximumIOPS_Value) -and ![string]::IsNullOrEmpty($MaximumIOPS)){ #SQL
                                            if($CustomPolicyIOPS_Value -eq $Gold -and $PolicyIOPS_MaximumIOPS -ne $MaximumIOPS){
                                                $MeasureVM.HardDiskMetrics | %{
                                                    Set-VMHardDiskDrive -ComputerName $VMHost.name -VMName $VMname -ControllerType $_.VirtualHardDisk.ControllerType `
                                                    -ControllerNumber $_.VirtualHardDisk.ControllerNumber -ControllerLocation $_.VirtualHardDisk.ControllerLocation -MaximumIOPS $Gold_size
                                                    if($?){$Change_VM = $true}
                                                }
                                                $SqlQuery = "
                                                    UPDATE dbo.[tbl_BTBS_CustomPropertyValue]
                                                    SET [Value] = '$($PolicyIOPS_MaximumIOPS)'
                                                    WHERE tbl_BTBS_CustomPropertyValue.ObjectID = '$($VM_ID)' AND tbl_BTBS_CustomPropertyValue.CustomPropertyID = '$($CustomMaximumIOPS_ID)';
                                                "
                                                $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
                                                $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                                                $SqlAdapter.SelectCommand = $SqlCmd
                                                $DataSet = New-Object System.Data.DataSet
                                                $SqlAdapter.Fill($DataSet)
                                                if($?){$Change_VM = $true}
                                            }elseif($CustomPolicyIOPS_Value -eq $Silver -and $PolicyIOPS_MaximumIOPS -ne $MaximumIOPS){
                                                $MeasureVM.HardDiskMetrics | %{
                                                    Set-VMHardDiskDrive -ComputerName $VMHost.name -VMName $VMname -ControllerType $_.VirtualHardDisk.ControllerType `
                                                    -ControllerNumber $_.VirtualHardDisk.ControllerNumber -ControllerLocation $_.VirtualHardDisk.ControllerLocation -MaximumIOPS $Silver_size
                                                    if($?){$Change_VM = $true}
                                                }
                                                $SqlQuery = "
                                                    UPDATE dbo.[tbl_BTBS_CustomPropertyValue]
                                                    SET [Value] = '$($PolicyIOPS_MaximumIOPS)'
                                                    WHERE tbl_BTBS_CustomPropertyValue.ObjectID = '$($VM_ID)' AND tbl_BTBS_CustomPropertyValue.CustomPropertyID = '$($CustomMaximumIOPS_ID)';
                                                "
                                                $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
                                                $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                                                $SqlAdapter.SelectCommand = $SqlCmd
                                                $DataSet = New-Object System.Data.DataSet
                                                $SqlAdapter.Fill($DataSet)
                                                if($?){$Change_VM = $true}
                                            }elseif($CustomPolicyIOPS_Value -eq $Bronze -and $PolicyIOPS_MaximumIOPS -ne $MaximumIOPS){
                                                $MeasureVM.HardDiskMetrics | %{
                                                    Set-VMHardDiskDrive -ComputerName $VMHost.name -VMName $VMname -ControllerType $_.VirtualHardDisk.ControllerType `
                                                    -ControllerNumber $_.VirtualHardDisk.ControllerNumber -ControllerLocation $_.VirtualHardDisk.ControllerLocation -MaximumIOPS $Bronze_size
                                                    if($?){$Change_VM = $true}
                                                }
                                                $SqlQuery = "
                                                    UPDATE dbo.[tbl_BTBS_CustomPropertyValue]
                                                    SET [Value] = '$($PolicyIOPS_MaximumIOPS)'
                                                    WHERE tbl_BTBS_CustomPropertyValue.ObjectID = '$($VM_ID)' AND tbl_BTBS_CustomPropertyValue.CustomPropertyID = '$($CustomMaximumIOPS_ID)';
                                                "
                                                $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
                                                $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                                                $SqlAdapter.SelectCommand = $SqlCmd
                                                $DataSet = New-Object System.Data.DataSet
                                                $SqlAdapter.Fill($DataSet)
                                                if($?){$Change_VM = $true}
                                            }elseif([string]::IsNullOrEmpty($CustomPolicyIOPS_Value) -and $PolicyIOPS_MaximumIOPS -ne $MaximumIOPS -and $MaximumIOPS -ne 0){
                                                $SqlQuery = "
                                                    UPDATE dbo.[tbl_BTBS_CustomPropertyValue]
                                                    SET [Value] = '$($MaximumIOPS)'
                                                    WHERE tbl_BTBS_CustomPropertyValue.ObjectID = '$($VM_ID)' AND tbl_BTBS_CustomPropertyValue.CustomPropertyID = '$($CustomMaximumIOPS_ID)';
                                                "
                                                $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
                                                $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                                                $SqlAdapter.SelectCommand = $SqlCmd
                                                $DataSet = New-Object System.Data.DataSet
                                                $SqlAdapter.Fill($DataSet)
                                                if($?){$Change_VM = $true}
                                            }elseif([string]::IsNullOrEmpty($CustomPolicyIOPS_Value) -and $MaximumIOPS -eq 0){
                                                $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomMaximumIOPS
                                                Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                                if($?){$Change_VM = $true}
                                            }
                                            <# Shvarev
                                            elseif([string]::IsNullOrEmpty($CustomPolicyIOPS_Value) -and ![string]::IsNullOrEmpty($CustomMaximumIOPS_Value)){
                                                $MeasureVM.HardDiskMetrics | %{
                                                    Set-VMHardDiskDrive -ComputerName $VMHost.name -VMName $VMname -ControllerType $_.VirtualHardDisk.ControllerType `
                                                    -ControllerNumber $_.VirtualHardDisk.ControllerNumber -ControllerLocation $_.VirtualHardDisk.ControllerLocation -MaximumIOPS 0
                                                    if($?){$Change_VM = $true}
                                                }
                                                $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomMaximumIOPS
                                                Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                                if($?){$Change_VM = $true}
                                            }#>
                                        }elseif(![string]::IsNullOrEmpty($MaximumIOPS)){ #VMM
                                            if($CustomPolicyIOPS_Value -eq $Gold -and $PolicyIOPS_MaximumIOPS -ne $MaximumIOPS){
                                                $MeasureVM.HardDiskMetrics | %{
                                                    Set-VMHardDiskDrive -ComputerName $VMHost.name -VMName $VMname -ControllerType $_.VirtualHardDisk.ControllerType `
                                                    -ControllerNumber $_.VirtualHardDisk.ControllerNumber -ControllerLocation $_.VirtualHardDisk.ControllerLocation -MaximumIOPS $Gold_size
                                                    if($?){$Change_VM = $true}
                                                }
                                                Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomMaximumIOPS -Value $PolicyIOPS_MaximumIOPS
                                                if($?){$Change_VM = $true}
                                            }elseif($CustomPolicyIOPS_Value -eq $Silver -and $PolicyIOPS_MaximumIOPS -ne $MaximumIOPS){
                                                $MeasureVM.HardDiskMetrics | %{
                                                    Set-VMHardDiskDrive -ComputerName $VMHost.name -VMName $VMname -ControllerType $_.VirtualHardDisk.ControllerType `
                                                    -ControllerNumber $_.VirtualHardDisk.ControllerNumber -ControllerLocation $_.VirtualHardDisk.ControllerLocation -MaximumIOPS $Silver_size
                                                    if($?){$Change_VM = $true}
                                                }
                                                Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomMaximumIOPS -Value $PolicyIOPS_MaximumIOPS
                                                if($?){$Change_VM = $true}
                                            }elseif($CustomPolicyIOPS_Value -eq $Bronze -and $PolicyIOPS_MaximumIOPS -ne $MaximumIOPS){
                                                $MeasureVM.HardDiskMetrics | %{
                                                    Set-VMHardDiskDrive -ComputerName $VMHost.name -VMName $VMname -ControllerType $_.VirtualHardDisk.ControllerType `
                                                    -ControllerNumber $_.VirtualHardDisk.ControllerNumber -ControllerLocation $_.VirtualHardDisk.ControllerLocation -MaximumIOPS $Bronze_size
                                                    if($?){$Change_VM = $true}
                                                }
                                                Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomMaximumIOPS -Value $PolicyIOPS_MaximumIOPS
                                                if($?){$Change_VM = $true}
                                            }elseif([string]::IsNullOrEmpty($CustomPolicyIOPS_Value) -and $PolicyIOPS_MaximumIOPS -ne $MaximumIOPS -and $MaximumIOPS -ne 0){
                                                Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomMaximumIOPS -Value $MaximumIOPS
                                                if($?){$Change_VM = $true}
                                            }elseif([string]::IsNullOrEmpty($CustomPolicyIOPS_Value) -and $MaximumIOPS -eq 0){
                                                $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomMaximumIOPS
                                                Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                                if($?){$Change_VM = $true}
                                            }
                                            <#elseif([string]::IsNullOrEmpty($CustomPolicyIOPS_Value) -and ![string]::IsNullOrEmpty($CustomMaximumIOPS_Value)){
                                                $MeasureVM.HardDiskMetrics | %{
                                                    Set-VMHardDiskDrive -ComputerName $VMHost.name -VMName $VMname -ControllerType $_.VirtualHardDisk.ControllerType `
                                                    -ControllerNumber $_.VirtualHardDisk.ControllerNumber -ControllerLocation $_.VirtualHardDisk.ControllerLocation -MaximumIOPS 0
                                                    if($?){$Change_VM = $true}
                                                }
                                                Remove-SCCustomPropertyValue -CustomPropertyValue $CustomMaximumIOPS_Value
                                                if($?){$Change_VM = $true}
                                            }#>
                                        }elseif(![string]::IsNullOrEmpty($CustomMaximumIOPS_Value)){ #Remove
                                            $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomMaximumIOPS
                                            Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                            if($?){$Change_VM = $true}
                                        }
                                    #LastSuccessfulBackupTime
                                        $VMConf = Get-WmiObject -ComputerName $VMHost.name -Namespace "root\virtualization\v2" -Query "SELECT * FROM Msvm_ComputerSystem WHERE ElementName like '$VMName' AND caption like 'Virtual%' "
                                        if([string]::IsNullOrEmpty($VMConf.LastSuccessfulBackupTime)){
                                            if(![string]::IsNullOrEmpty($CustomLastSuccessfulBackupTime_Value)){
                                                $Custom_Value = Get-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomLastSuccessfulBackupTime
                                                Remove-SCCustomPropertyValue -CustomPropertyValue $Custom_Value
                                                if($?){$Change_VM = $true}
                                            }
                                        }else{
                                            $TimeStamp = $VMConf.LastSuccessfulBackupTime -replace "[.].*$",""
                                            $LastSuccessfulBackupTime = $TimeStamp -replace '^(....)(..)(..)(..)(..)(..)$','$1.$2.$3 $4:$5:$6'
                                            if(![string]::IsNullOrEmpty($LastSuccessfulBackupTime) -and ![string]::IsNullOrEmpty($CustomLastSuccessfulBackupTime_Value) -and $CustomLastSuccessfulBackupTime_Value -ne $LastSuccessfulBackupTime){
                                                $SqlQuery = "
                                                    UPDATE dbo.[tbl_BTBS_CustomPropertyValue]
                                                    SET [Value] = '$($LastSuccessfulBackupTime)'
                                                    WHERE tbl_BTBS_CustomPropertyValue.ObjectID = '$($VM_ID)' AND tbl_BTBS_CustomPropertyValue.CustomPropertyID = '$($CustomLastSuccessfulBackupTime_ID)';
                                                "
                                                $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
                                                $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                                                $SqlAdapter.SelectCommand = $SqlCmd
                                                $DataSet = New-Object System.Data.DataSet
                                                $SqlAdapter.Fill($DataSet)
                                                if($?){$Change_VM = $true}
                                            }elseif(![string]::IsNullOrEmpty($LastSuccessfulBackupTime) -and $CustomLastSuccessfulBackupTime_Value -ne $LastSuccessfulBackupTime){
                                                Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomLastSuccessfulBackupTime -Value $LastSuccessfulBackupTime
                                                if($?){$Change_VM = $true}
                                            }
                                        }
                                }
                                #Refresh VM when all tasks are ended
                                if($Change_VM){
                                    #CustomDynamicStatus_Value
                                        $SqlQuery = "
	                                        SELECT * FROM VirtualManagerDB.dbo.tbl_BTBS_CustomPropertyValue
                                            WHERE tbl_BTBS_CustomPropertyValue.ObjectID = '$($VM_ID)' AND tbl_BTBS_CustomPropertyValue.CustomPropertyID = '$($CustomDynamicStatus_ID)';
                                        "
                                        $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
                                        $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                                        $SqlAdapter.SelectCommand = $SqlCmd
                                        $DataSet = New-Object System.Data.DataSet
                                        $SqlAdapter.Fill($DataSet)
                                        $CustomDynamicStatus_Value = $DataSet.Tables[0].Value
                                    #CustomDynamicStatus
                                        $CustomDynamicStatus_date = Get-Date -Format "dd.MM.yyyy HH:mm:ss"
                                        if(![string]::IsNullOrEmpty($CustomDynamicStatus_Value)){
                                            $SqlQuery = "
                                                UPDATE dbo.[tbl_BTBS_CustomPropertyValue]
                                                SET [Value] = '$($CustomDynamicStatus_date)'
                                                WHERE tbl_BTBS_CustomPropertyValue.ObjectID = '$($VM_ID)' AND tbl_BTBS_CustomPropertyValue.CustomPropertyID = '$($CustomDynamicStatus_ID)';
                                            "
                                            $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($SqlQuery,$SqlConnection)
                                            $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                                            $SqlAdapter.SelectCommand = $SqlCmd
                                            $DataSet = New-Object System.Data.DataSet
                                            $SqlAdapter.Fill($DataSet)
                                        }elseif(![string]::IsNullOrEmpty($CustomDynamicStatus_date)){
                                            Set-SCCustomPropertyValue -InputObject $VM -CustomProperty $CustomDynamicStatus -Value $CustomDynamicStatus_date
                                        }
                                    #alert MS is begger than 200000
                                        if($MeasureVM.AggregatedAverageLatency -ge $MS){
                                            email -FunctionVMname $VMname -FunctionAverageLatency $MeasureVM.AggregatedAverageLatency -FunctionAverageIOPS `
                                            $MeasureVM.AggregatedAverageNormalizedIOPS -FunctionMaximumIOPS $MaximumIOPS -FunctionPolicyIOPS $CustomPolicyIOPS_Value `
                                            -FunctionLocation $VM.DiskResources.name -FunctionMeteringDuration $MeasureVM.MeteringDuration -FunctionMS $MS `
                                            -FunctionIS $VM.CustomProperty.ИС
                                        }
                                    Refresh-VM -VM $VMName
                                }
                            }
                        }else{}
                    }
                    start-sleep -Seconds 5
            }
        }).BeginInvoke()
        start-sleep -Seconds 5
        $n++
    }else{
        if(!$HyperV_Hash.Array_part_VMHosts[$n] -and $HyperV_Hash.Number_Hosts -ne $Number_Hosts_eq){
            $n=0
        }
        $Number_Hosts_eq = $HyperV_Hash.Number_Hosts
        Start-Sleep -Seconds 5                                                                                              
    }
}
pause