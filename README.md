# SWISS Chocolatey
**S**et up a **W**orkstation **I**nstantly with a **S**imple **S**tatement... using **Chocolatey**!

This repo is used to set up a Win11 workstation host with disposable Hyper-V containers for working on projects in a clean environment. It supports both public and private repositories.

## Usage

* Install a fresh copy of **Windows 11 Pro**
* Install graphics drivers manually ([nvidia](https://www.nvidia.com/en-us/geforce/drivers/))
* Set up a [GitHub Personal Access Token](https://github.com/settings/tokens) with `repo` and `org:read` scopes
* Optional: install [Parsec](https://parsec.app/) manually to meta-manage remotely

### First time host setup

On the host, press `Win+X,A` to open an administrator PowerShell terminal

Copy+Paste the bootstrap script into PowerShell:

````
Set-ExecutionPolicy Bypass -Scope Process -Force ; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072 ; Invoke-WebRequest -Method Get -Uri ($__URL = (Read-Host -Prompt "Update-SwissHost.ps1") -replace "github\.com\/(.*)\/blob\/(.*)",'raw.githubusercontent.com/$1/$2') -Headers @{Authorization=@('token ',($__TOKEN = Read-Host -Prompt "GitHub Token")) -join ''; 'Cache-Control'='no-cache'} | ForEach-Object { $_.Content } | Invoke-Expression ; Update-SwissHost -Bootstrap @{Token=$__TOKEN; Url=$__URL} ; Remove-Variable @('__TOKEN','__URL')
````

Next, you will be asked for two additional inputs.

1. Copy-paste the URL to `Update-SwissHost.ps1` into the first prompt: [Update-SwissHost.ps1](./Module/Host/Update-SwissHost.ps1)
2. Paste your [GitHub Personal Access Token](https://github.com/settings/tokens) into the second prompt

Bootstrapping will then continue. If this is the first time you're running this on a fresh host, installing Hyper-V will require restarting your computer. The updater will automatically continue afterward.

Once the setup script completes, you're ready to install a VM. If you make changes to the swiss-chocolatey repository, your host will automatically update to the latest contents every time the host is restarted or `Update-SwissHost` is invoked.

### Configuring a repository

To use a repository as a VM, create a file named `/.swiss/config.json` to configure its settings.

### Managing a VM

On the host in an administrator PowerShell terminal with any of these commands:

```
Add-SwissVM
Add-SwissVM <repository>
Add-SwissVM -Repository <repository> -Branch <branch> -VMName <name>
```

By default, `Add-SwissVM` reads from the `main` branch and will create a VM with the same name as the repository.

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

### Other useful commands

* If you're not sure which VM's are available, use `Get-SwissVM` for a list
