param location string
param networkInterfaceName string
param subnetId string
param pipDeleteOption string
param vmName string
param virtualMachineComputerName string
param osDiskType string
param osDiskDeleteOption string
param dataDisks array
param dataDiskResources array
param virtualMachineSize string
param nicDeleteOption string
param adminUsername string

@secure()
param adminPassword string
param patchMode string
param enableHotpatching bool
param sqlVirtualMachineLocation string
param sqlvmName string
param sqlConnectivityType string
param sqlPortNumber int
param sqlStorageWorkloadType string
param sqlStorageDisksConfigurationType string
param sqlAutopatchingDayOfWeek string
param sqlAutopatchingStartHour int
param sqlAutopatchingWindowDuration int
param dataPath string
param dataDisksLUNs array
param logPath string
param logDisksLUNs array
param tempDbPath string
param dataFileCount int
param dataFileSize int
param dataGrowth int
param logFileSize int
param logGrowth int
param SQLSystemDbOnDataDisk bool
param rServicesEnabled bool
param maxdop int
param isOptimizeForAdHocWorkloadsEnabled bool
param collation string
param minServerMemoryMB int
param maxServerMemoryMB int



// Create the virtual machine's public IP address
resource pip 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: '${vmName}-pip'
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    publicIPAllocationMethod: 'Dynamic'
    dnsSettings: {
      domainNameLabel: toLower('${vmName}-${uniqueString(resourceGroup().id, vmName)}')
    }
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2021-08-01' = {
  name: networkInterfaceName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: pip.id
            properties: {
              deleteOption: pipDeleteOption
            }
          }
        }
      }
    ]
  }
}

resource dataDiskResources_name 'Microsoft.Compute/disks@2022-03-02' = [for item in dataDiskResources: {
  name: item.name
  location: location
  properties: item.properties
  sku: {
    name: item.sku
  }
  tags: {
    Env: 'dev'
  }
}]

resource virtualMachine 'Microsoft.Compute/virtualMachines@2022-03-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: virtualMachineSize
    }
    storageProfile: {
      osDisk: {
        createOption: 'fromImage'
        managedDisk: {
          storageAccountType: osDiskType
        }
        deleteOption: osDiskDeleteOption
      }
      imageReference: {
        publisher: 'microsoftsqlserver'
        offer: 'sql2019-ws2022'
        sku: 'sqldev-gen2'
        version: 'latest'
      }
      dataDisks: [for item in dataDisks: {
        lun: item.lun
        createOption: item.createOption
        caching: item.caching
        diskSizeGB: item.diskSizeGB
        managedDisk: {
          id: (item.id ?? ((item.name == json('null')) ? json('null') : resourceId('Microsoft.Compute/disks', item.name)))
          storageAccountType: item.storageAccountType
        }
        deleteOption: item.deleteOption
        writeAcceleratorEnabled: item.writeAcceleratorEnabled
      }]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
          properties: {
            deleteOption: nicDeleteOption
          }
        }
      ]
    }
    osProfile: {
      computerName: virtualMachineComputerName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
        patchSettings: {
          enableHotpatching: enableHotpatching
          patchMode: patchMode
        }
      }
    }
    licenseType: 'Windows_Server'
  }
  tags: {
    Env: 'dev'
  }
  dependsOn: [
    dataDiskResources_name

  ]
}

resource sqlVirtualMachine 'Microsoft.SqlVirtualMachine/SqlVirtualMachines@2021-11-01-preview' = {
  name: sqlvmName
  location: sqlVirtualMachineLocation
  properties: {
    virtualMachineResourceId: resourceId('Microsoft.Compute/virtualMachines', sqlvmName)
    sqlManagement: 'Full'
    sqlServerLicenseType: 'PAYG'
    autoPatchingSettings: {
      enable: true
      dayOfWeek: sqlAutopatchingDayOfWeek
      maintenanceWindowStartingHour: sqlAutopatchingStartHour
      maintenanceWindowDuration: sqlAutopatchingWindowDuration
    }
    keyVaultCredentialSettings: {
      enable: false
      credentialName: ''
    }
    storageConfigurationSettings: {
      diskConfigurationType: sqlStorageDisksConfigurationType
      storageWorkloadType: sqlStorageWorkloadType
      sqlDataSettings: {
        luns: dataDisksLUNs
        defaultFilePath: dataPath
      }
      sqlLogSettings: {
        luns: logDisksLUNs
        defaultFilePath: logPath
      }
      sqlTempDbSettings: {
        defaultFilePath: tempDbPath
        dataFileCount: dataFileCount
        dataFileSize: dataFileSize
        dataGrowth: dataGrowth
        logFileSize: logFileSize
        logGrowth: logGrowth
      }
      sqlSystemDbOnDataDisk: SQLSystemDbOnDataDisk
    }
    serverConfigurationsManagementSettings: {
      sqlConnectivityUpdateSettings: {
        connectivityType: sqlConnectivityType
        port: sqlPortNumber
        sqlAuthUpdateUserName: ''
        sqlAuthUpdatePassword: ''
      }
      additionalFeaturesServerConfigurations: {
        isRServicesEnabled: rServicesEnabled
      }
      sqlInstanceSettings: {
        maxDop: maxdop
        isOptimizeForAdHocWorkloadsEnabled: isOptimizeForAdHocWorkloadsEnabled
        collation: collation
        minServerMemoryMB: minServerMemoryMB
        maxServerMemoryMB: maxServerMemoryMB
      }
    }
  }
  dependsOn: [
    virtualMachine
  ]
}

output adminUsername string = adminUsername
