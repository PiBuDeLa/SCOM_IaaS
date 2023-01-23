// Deployment parameters
@description('Location to depoloy all resources. Leave this value as-is to inherit the location from the parent resource group.')
param location string = resourceGroup().location

// Virtual network parameters
@description('Name for the virtual network.')
param virtualNetworkName string = 'VNET'

@description('Address space for the virtual network, in IPv4 CIDR notation.')
param virtualNetworkAddressSpace string = '10.0.0.0/16'

@description('Name for the default subnet in the virtual network.')
param subnetName string = 'Subnet'

@description('Address range for the default subnet, in IPv4 CIDR notation.')
param subnetAddressRange string = '10.0.0.0/24'

@description('Public IP address of your local machine, in IPv4 CIDR notation. Used to restrict remote access to resources within the virtual network.')
param allowedSourceIPAddress string = '0.0.0.0/0'

// Virtual machine parameters
@description('Name for the domain controller virtual machine.')
param domainControllerName string = 'DC01'

@description('Name for the workstation virtual machine.')
param workstationName string = 'WS01'

@description('Name for the SQL server virtual machine.')
param SQLserverName string = 'SQL01'

@description('Name for the workstation virtual machine.')
param SCOMserverName string = 'SCOM01'


@description('Size for both the domain controller and workstation virtual machines.')
@allowed([
  'Standard_DS1_v2'
  'Standard_D2s_v3'
])
param virtualMachineSize string = 'Standard_DS1_v2'

// Domain parameters
@description('FQDN for the Active Directory domain (e.g. contoso.com).')
@minLength(3)
@maxLength(255)
param domainFQDN string = 'contoso.com'

@description('Administrator username for both the domain controller and workstation virtual machines.')
@minLength(1)
@maxLength(20)
param adminUsername string = 'pibudela'

@description('Administrator password for both the domain controller and workstation virtual machines.')
@minLength(12)
@maxLength(123)
@secure()
param adminPassword string


// Deploy the virtual network
module virtualNetwork 'modules/network.bicep' = {
  name: 'virtualNetwork'
  params: {
    location: location
    virtualNetworkName: virtualNetworkName
    virtualNetworkAddressSpace: virtualNetworkAddressSpace
    subnetName: subnetName
    subnetAddressRange: subnetAddressRange
    allowedSourceIPAddress: allowedSourceIPAddress
  }
}

// Deploy the domain controller
module domainController 'modules/vm.bicep' = {
  name: 'domainController'
  params: {
    location: location
    subnetId: virtualNetwork.outputs.subnetId
    vmName: domainControllerName
    vmSize: virtualMachineSize
    vmPublisher: 'MicrosoftWindowsServer'
    vmOffer: 'WindowsServer'
    vmSku: '2019-Datacenter'
    vmVersion: 'latest'
    vmStorageAccountType: 'StandardSSD_LRS'
    adminUsername: adminUsername
    adminPassword: adminPassword
  }
}

// Use PowerShell DSC to deploy Active Directory Domain Services on the domain controller
resource domainControllerConfiguration 'Microsoft.Compute/virtualMachines/extensions@2021-11-01' = {
  name: '${domainControllerName}/Microsoft.Powershell.DSC'
  dependsOn: [
    domainController
  ]
  location: location
  properties: {
    publisher: 'Microsoft.Powershell'
    type: 'DSC'
    typeHandlerVersion: '2.77'
    autoUpgradeMinorVersion: true
    settings: {
      ModulesUrl: 'https://github.com/joshua-a-lucas/BlueTeamLab/raw/main/scripts/Deploy-DomainServices.zip'
      ConfigurationFunction: 'Deploy-DomainServices.ps1\\Deploy-DomainServices'
      Properties: {
        domainFQDN: domainFQDN
        adminCredential: {
          UserName: adminUsername
          Password: 'PrivateSettingsRef:adminPassword'
        }
      }
    }
    protectedSettings: {
      Items: {
          adminPassword: adminPassword
      }
    }
  }
}

// Update the virtual network with the domain controller as the primary DNS server
module virtualNetworkDNS 'modules/network.bicep' = {
  name: 'virtualNetworkDNS'
  dependsOn: [
    domainControllerConfiguration
  ]
  params: {
    location: location
    virtualNetworkName: virtualNetworkName
    virtualNetworkAddressSpace: virtualNetworkAddressSpace
    subnetName: subnetName
    subnetAddressRange: subnetAddressRange
    allowedSourceIPAddress: allowedSourceIPAddress
    dnsServerIPAddress: domainController.outputs.privateIpAddress
  }
}



// Deploy the SQLserver 
module SQLserver 'modules/SQL.bicep' = {
  name: 'SQLserver'
  params: {
    location: location
    networkInterfaceName: '${SQLserverName}-nic'
    subnetId: virtualNetwork.outputs.subnetId
    pipDeleteOption: 'Delete'
    vmName: SQLserverName
    virtualMachineComputerName: SQLserverName
    osDiskType: 'Standard_LRS'
    osDiskDeleteOption: 'Delete'
    dataDisks: [
            {
                lun: 0
                createOption: 'attach'
                deleteOption: 'Detach'
                caching: 'ReadOnly'
                writeAcceleratorEnabled: false
                id: null
                name: '${SQLserverName}_DataDisk_0'
                storageAccountType: null
                diskSizeGB: null
                diskEncryptionSet: null
            }
        ]
    dataDiskResources: [
            {
                name: '${SQLserverName}_DataDisk_0'
                sku: 'Premium_LRS'
                properties: {
                    diskSizeGB: 32
                    creationData: {
                        createOption: 'empty'
                    }
                }
            }
        ]
    virtualMachineSize: 'Standard_B2ms'
    nicDeleteOption: 'Delete'
    adminUsername: adminUsername
    adminPassword: adminPassword
    patchMode: 'AutomaticByOS'
    enableHotpatching: false
    sqlVirtualMachineLocation: 'westeurope'
    sqlvmName: SQLserverName
    sqlConnectivityType: 'Private'
    sqlPortNumber: 1433
    sqlStorageWorkloadType: 'OLTP'
    sqlStorageDisksConfigurationType: 'NEW'
    sqlAutopatchingDayOfWeek: 'Sunday'
    sqlAutopatchingStartHour: 2
    sqlAutopatchingWindowDuration: 60
    dataPath: 'F:\\data'
    dataDisksLUNs: [
            0
        ]
    logPath: 'F:\\log'
    logDisksLUNs: [
            0
        ]
    tempDbPath: 'D:\\tempDb'
    dataFileCount: 2
    dataFileSize: 512
    dataGrowth: 512
    logFileSize: 8
    logGrowth: 64
    SQLSystemDbOnDataDisk: false
    rServicesEnabled: false
    maxdop: 0
    isOptimizeForAdHocWorkloadsEnabled: false
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    minServerMemoryMB: 0
    maxServerMemoryMB: 2147483647
  }
}

// Use PowerShell DSC to join the SQLserver to the domain
resource SQLserverConfiguration 'Microsoft.Compute/virtualMachines/extensions@2021-11-01' = {
  name: '${SQLserverName}/Microsoft.Powershell.DSC'
  dependsOn: [
    SQLserver
  ]
  location: location
  properties: {
    publisher: 'Microsoft.Powershell'
    type: 'DSC'
    typeHandlerVersion: '2.77'
    autoUpgradeMinorVersion: true
    settings: {
      ModulesUrl: 'https://github.com/joshua-a-lucas/BlueTeamLab/raw/main/scripts/Join-Domain.zip'
      ConfigurationFunction: 'Join-Domain.ps1\\Join-Domain'
      Properties: {
        domainFQDN: domainFQDN
        computerName: SQLserverName
        adminCredential: {
          UserName: adminUsername
          Password: 'PrivateSettingsRef:adminPassword'
        }
      }
    }
    protectedSettings: {
      Items: {
          adminPassword: adminPassword
      }
    }
  }
}




// Deploy the SCOMserverConfiguration
module SCOMserver 'modules/vm.bicep' = {
  name: 'SCOMserver'
  params: {
    location: location
    subnetId: virtualNetwork.outputs.subnetId
    vmName: SCOMserverName
    vmSize: virtualMachineSize
    vmPublisher: 'MicrosoftWindowsServer'
    vmOffer: 'WindowsServer'
    vmSku: '2019-Datacenter'
    vmVersion: 'latest'
    vmStorageAccountType: 'StandardSSD_LRS'
    adminUsername: adminUsername
    adminPassword: adminPassword
  }
}

// Use PowerShell DSC to join the SCOMserverConfiguration to the domain
resource SCOMserverConfiguration 'Microsoft.Compute/virtualMachines/extensions@2021-11-01' = {
  name: '${SCOMserverName}/Microsoft.Powershell.DSC'
  dependsOn: [
    SCOMserver
  ]
  location: location
  properties: {
    publisher: 'Microsoft.Powershell'
    type: 'DSC'
    typeHandlerVersion: '2.77'
    autoUpgradeMinorVersion: true
    settings: {
      ModulesUrl: 'https://github.com/joshua-a-lucas/BlueTeamLab/raw/main/scripts/Join-Domain.zip'
      ConfigurationFunction: 'Join-Domain.ps1\\Join-Domain'
      Properties: {
        domainFQDN: domainFQDN
        computerName: SCOMserverName
        adminCredential: {
          UserName: adminUsername
          Password: 'PrivateSettingsRef:adminPassword'
        }
      }
    }
    protectedSettings: {
      Items: {
          adminPassword: adminPassword
      }
    }
  }
}

// Create GMSA Account

// Install SCOM


// Deploy the workstation once the virtual network's primary DNS server has been updated to the domain controller
module workstation 'modules/vm.bicep' = {
  name: 'workstation'
  dependsOn: [
    virtualNetworkDNS
  ]
  params: {
    location: location
    subnetId: virtualNetwork.outputs.subnetId
    vmName: workstationName
    vmSize: virtualMachineSize
    vmPublisher: 'microsoftvisualstudio'
    vmOffer: 'visualstudio2019latest'
    vmSku: 'vs-2019-ent-latest-win11-n-gen2'
    vmVersion: 'latest'
    vmStorageAccountType: 'StandardSSD_LRS'
    adminUsername: adminUsername
    adminPassword: adminPassword
  }
}

// Use PowerShell DSC to join the workstation to the domain
resource workstationConfiguration 'Microsoft.Compute/virtualMachines/extensions@2021-11-01' = {
  name: '${workstationName}/Microsoft.Powershell.DSC'
  dependsOn: [
    workstation
  ]
  location: location
  properties: {
    publisher: 'Microsoft.Powershell'
    type: 'DSC'
    typeHandlerVersion: '2.77'
    autoUpgradeMinorVersion: true
    settings: {
      ModulesUrl: 'https://github.com/joshua-a-lucas/BlueTeamLab/raw/main/scripts/Join-Domain.zip'
      ConfigurationFunction: 'Join-Domain.ps1\\Join-Domain'
      Properties: {
        domainFQDN: domainFQDN
        computerName: workstationName
        adminCredential: {
          UserName: adminUsername
          Password: 'PrivateSettingsRef:adminPassword'
        }
      }
    }
    protectedSettings: {
      Items: {
          adminPassword: adminPassword
      }
    }
  }
}
