# Set Date window to 28 days for data set
$date = (Get-Date).AddDays(-28)

# Set resource ID for VM
$id="INSERT RESOURCE ID"

# Output 15 minute time grain for CPU Percentage, Uses average property
$cpuoutput = Get-AzMetric -ResourceId $id -AggregationType Average -StartTime $date -TimeGrain 00:15:00 -MetricNames "Percentage CPU"
$cpufinal = $cpuoutput.data | Measure-Object -Property Average -Average
$cpufinal | Format-Table @{Label=”Average CPU Percentage”;Expression= {“{0:P}” -f ($_.average / 100)}}

# Output 15 minute time grain for Available Memory Bytes, Uses minimum property
$memoutput = Get-AzMetric -ResourceId $id -AggregationType Minimum -StartTime $date -TimeGrain 00:15:00 -MetricNames "Available Memory Bytes"
$memfinal = $memoutput.data | Measure-Object -Property Minimum -Minimum
$memfinal | Format-Table @{Label=”Minimum Available Memory GB”;Expression= {“{0:N2}” -f ($_.minimum / 1073741824)}}

# Output 15 minute time grain for VM Cached IOPS Consumed Percentage, Uses max property
$vmcachediopsoutput = Get-AzMetric -ResourceId $id -AggregationType Maximum -StartTime $date -TimeGrain 00:15:00 -MetricNames "VM Cached IOPS Consumed Percentage"
$vmcachediopsfinal = $vmcachediopsoutput.data | Measure-Object -Property Maximum -Maximum
$vmcachediopsfinal | Format-Table @{Label=”Maximum VM Cached IOPS”;Expression= {“{0:P}” -f ($_.maximum / 100)}}

# Output 15 minute time grain for VM Uncached IOPS Consumed Percentage, Uses max property
$vmuncachediopsoutput = Get-AzMetric -ResourceId $id -AggregationType Maximum -StartTime $date -TimeGrain 00:15:00 -MetricNames "VM Uncached IOPS Consumed Percentage"
$vmuncachediopsfinal = $vmuncachediopsoutput.data | Measure-Object -Property Maximum -Maximum
$vmuncachediopsfinal | Format-Table @{Label=”Maximum VM Uncached IOPS”;Expression= {“{0:P}” -f ($_.maximum / 100)}}

# Output 15 minute time grain for OS Disk IOPS Consumed Percentage, Uses max property
$osdiskiopsoutput = Get-AzMetric -ResourceId $id -AggregationType Maximum -StartTime $date -TimeGrain 00:15:00 -MetricNames "OS Disk IOPS Consumed Percentage"
$osdiskiopsfinal = $osdiskiopsoutput.data | Measure-Object -Property Maximum -Maximum
$osdiskiopsfinal | Format-Table @{Label=”Maximum OS Disk IOPS”;Expression= {“{0:P}” -f ($_.maximum / 100)}}

# Output 15 minute time grain for Data Disk IOPS Consumed Percentage, Uses max property
$datadiskiopsoutput = Get-AzMetric -ResourceId $id -AggregationType Maximum -StartTime $date -TimeGrain 00:15:00 -MetricNames "Data Disk IOPS Consumed Percentage"
$datadiskiopsfinal = $datadiskiopsoutput.data | Measure-Object -Property Maximum -Maximum
$datadiskiopsfinal | Format-Table @{Label=”Maximum Data Disk IOPS”;Expression= {“{0:P}” -f ($_.maximum / 100)}}