Import-Module ServerManager
Add-WindowsFeature Adcs-Cert-Authority -IncludeManagementTools
Install-AdcsCertificationAuthority -force -CAType EnterpriseRootCa
