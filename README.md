# UpgradeVMM
Скрипт заполняет значения в custom-свойства консоли Virtual Machine Manager, 24\7.

Опубликованы два скрипта, скрипт под названием Dynamic, постоянно обновляет меняющиеся значения:
CustomUptime - сколько времени работате гостевая машина.
CustomUptimeHost - сколько времени работает гостевая машина на хосте.
CustomLastSuccessfulBackupTime - последняя дата выполнения бэкапа.
CustomAverageIOPS - среднее значение IOPS за секунду, для VHD-диска, каждый IO - 8KB.
CustomAverageLatency - среднее время задержки в МС.
CustomDynamicStatus - время публикации динамический значений.
CustomMaximumIOPS - порог максимального значения IOPS.
CustomPolicyIOPS - политика значений IOPS (bronze, silver, gold).
CustomMeteringDuration - время за которое было собрано значение среднее значение IOPS и задержка.

Скрипт Static меняет зачения статичные:
CustomVLAN - VLAN виртуальной сети.
CustomSCCMClient - установлен ли агент SCCM на гостевой машине.
CustomSectorSize - размер блока VHD.
CustomLocation - расположение VHD на томе.
CustomVirtualizationPlatform - к какой платформе принадлежит гостевая машина.
CustomVMCheckpoints.
  
![UpgradeVMM](https://user-images.githubusercontent.com/30699602/125201668-55f6a300-e29a-11eb-8ff6-7c6950d31d59.jpg)
