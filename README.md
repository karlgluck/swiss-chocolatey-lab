# SWISS Chocolatey Lab
**S**et up a **W**orkstation **I**nstantly with **S**imple **S**cripts... using [Chocolatey](https://chocolatey.org/) and [AutomatedLab](https://automatedlab.org/)!

Swiss Chocolatey Lab (SCL) runs disposable developer environments on a Windows 11 PC. It supports both public and private repositories.

## Usage

* Install a fresh copy of **Windows 11 Pro**
* Install graphics drivers manually ([nvidia](https://www.nvidia.com/en-us/geforce/drivers/))
* Set up a [GitHub Personal Access Token](https://github.com/settings/tokens) with `repo` and `org:read` scopes
* Optional: install [Parsec](https://parsec.app/) manually to meta-manage remotely

## Quick Start - Windows Sandbox

The easiest way to experiment with SCL is to run it in a [Windows Sandbox](https://docs.microsoft.com/en-us/windows/security/threat-protection/windows-sandbox/windows-sandbox-overview). Copy and paste this command into an admin PowerShell terminal in your sandbox:

```
Set-ExecutionPolicy Bypass -Scope Process -Force ; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072 ; (Invoke-WebRequest -Method Get -Uri ($__URL = (Read-Host -Prompt "Update-SwissSandbox.ps1") -replace "github\.com\/(.*)\/blob\/(.*)",'raw.githubusercontent.com/$1/$2') -Headers @{Authorization=@('token ',($__TOKEN = Read-Host -Prompt "GitHub Token")) -join ''; 'Cache-Control'='no-store'}).Content | Invoke-Expression ; Update-SwissHost -Bootstrap ([PSCustomObject]@{Token=$__TOKEN; HostUrl=$__URL; GuestUrl=(Read-Host -Prompt "GitHub Repository")}) ; Remove-Variable @('__TOKEN','__URL')
```

You will be asked to provide three additional inputs:

1. Copy-paste the URL to [Update-SwissSandbox.ps1](./Module/Sandbox/Update-SwissSandbox.ps1) into the first prompt for "Update-SwissSandbox.ps1"
2. Paste your [GitHub Personal Access Token](https://github.com/settings/tokens) into the second prompt for "GitHub Token"
3. Paste the URL of the repository you want to load into the third prompt for "GitHub Repository"

The configuration defined in the target repository's `.swiss` directory is used to set up the sandbox environment. If the repository doesn't have one, you can explore using `choco install \<package name>` to [install packages](https://community.chocolatey.org/packages). Once setup completes, you'll find the repository available under the C:/ drive.

The major limitation to running SCL in a sandbox is that everything is lost when it shuts down. This means you can't install software that requires rebooting or save your session when the host restarts.

## Full Install - Hyper-V

SCL can also use Hyper-V to create developer environments. This will let you pause, resume and even checkpoint your environments.

SCL is built to run on a fresh installation of Windows 11 that does nothing but host these VM's, and there is currently no uninstall script. It doesn't do anything irreversible, but the changes to the environment can be extensive.

To get started, press `Win+X,A` to open an admin PowerShell terminal. Then, copy and paste the following bootstrap script into PowerShell:

````
Set-ExecutionPolicy Bypass -Scope Process -Force ; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072 ; (Invoke-WebRequest -Method Get -Uri ($__URL = (Read-Host -Prompt "Update-SwissHost.ps1") -replace "github\.com\/(.*)\/blob\/(.*)",'raw.githubusercontent.com/$1/$2') -Headers @{Authorization=@('token ',($__TOKEN = Read-Host -Prompt "GitHub Token")) -join ''; 'Cache-Control'='no-store'}).Content | Invoke-Expression ; Update-SwissHost -Bootstrap ([PSCustomObject]@{Token=$__TOKEN; Url=$__URL}) ; Remove-Variable @('__TOKEN','__URL')
````

You will be asked to provide two additional inputs:

1. Copy-paste the URL to [Update-SwissHost.ps1](./Module/Host/Update-SwissHost.ps1) into the first prompt for "Update-SwissHost.ps1"
2. Paste your [GitHub Personal Access Token](https://github.com/settings/tokens) into the second prompt for "GitHub Token"

Bootstrapping will then continue. If this is the first time you're running this on a fresh host, installing Hyper-V will require restarting your computer. You will need to manually run `Update-SwissHost` after rebooting to continue.

Once the setup script completes, you're ready to install a virtual machine.


## Managing a VM

On the host in an administrator PowerShell terminal with any of these commands:

```
New-SwissVM
New-SwissVM <repository>
New-SwissVM -Repository <repository> -Branch <branch> -VMName <name> -UseCommonConfig <name>
```

By default, `Add-SwissVM` reads from the `main` branch and will create a VM with the same name as the repository.

`-UseCommonConfig` allows you to install a SwissVM without having to edit the repository by grabbing one of the `*.swissguest` files from the [Config](./Config) folder in this repository.

Login credentials will be your GitHub username with the name of the repository as a password.

After creation, launch the VM on the host:

```
Start-SwissVM <name>
```

Once connected to a VM, you can always update the environment:

```
GUEST> Update-SwissVM
```

Once you're done with a VM, disposing of it on the host is done with:

```
Remove-SwissVM <name>
```


## Configuring a repository

Repositories use the `/.swiss` subdirectory to store their own environment setup configuration and scripts:

| File                    | Description                                                             |
|-------------------------|-------------------------------------------------------------------------|
|`/.swiss/config.json`    | Top-level configuration object. [Example](Config/Generic4GB.swissguest) |
|`/.swiss/packages.config`| Chocolatey package file definition, installed and updated automatically |



## Other useful commands

* If you're not sure which VM's are available, use `Get-SwissVM` for a list
