<# 
If not installed, you must first install chocolatey:

# Install Chocolatey
Set-ExecutionPolicy RemoteSigned -Force
# Create empty profile (so profile-integration scripts have something to append to)
if (-not (Test-Path $PROFILE)) {
    $directory = [IO.Path]::GetDirectoryName($PROFILE)
    if (-not (Test-Path $directory)) {
        New-Item -ItemType Directory $directory | Out-Null
    }
    
    "# Profile" > $PROFILE
}

iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
#>

function generateShortGuid() { $g = [guid]::newguid().ToString(); $g.substring(0, $g.indexOf('-')); }

<#
.SYNOPSIS
Installs the Build Agent for Azure (or TFS) along with the minimum Visual Studio component workloads required for a build agent to work.

.DESCRIPTION
Long description

.PARAMETER buildAgent_Url
The Azure or TFS URL

.PARAMETER buildAgent_PATToken
PAT token generated in Azure (or TFS) for administrative tasks

.PARAMETER buildAgent_LogonUsername
The logon username for the user to be used by the service

.PARAMETER buildAgent_LogonPassword
The logon password for the user to be used by the service

.PARAMETER buildAgent_AgentName
Name of the build agent being created; if left blank, will auto-generate a name

.PARAMETER buildTools_installPath
The path to install the build tools; if left blank, will install in the default location

.PARAMETER testAgent_installPath
The path to install the test agent; if left blank, will install in the default location

.PARAMETER buildAgent_installDirectory
The directory to install the build agent; if left blank, will install to the default location C:\build-agents

.PARAMETER buildTools_componentsToInstall
An array of strings referring to ComponentIDs (full list here https://docs.microsoft.com/en-us/visualstudio/install/workload-component-id-vs-build-tools?vs-2017&view=vs-2017). Defaults to the most commonly needed (.net, .net core, web, data, node)

.PARAMETER buildAgent_bitness
The bitness of the Build Agent to install. 32 or 64; defaults to 64

.EXAMPLE
Install-BuildAgent -buildAgent_Url "https://tfsinstance.yourdomain.com/tfs/" -buildAgent_PATToken "asdf1234" -buildAgent_LogonUsername "USERNAME" -buildAgent_LogonPassword "PASSWORD" -buildTools_installPath "C:\VisualStudio2017BuildTools" -testAgent_installPath "C:\VisualStudio2017TestAgent" -buildAgent_installDirectory "C:\build-agents"
#>
function Install-BuildAgent {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)][string]$buildAgent_Url,
        [Parameter(Mandatory = $true)][string]$buildAgent_PATToken,
        [Parameter(Mandatory = $true)][string]$buildAgent_LogonUsername,
        [Parameter(Mandatory = $true)][string]$buildAgent_LogonPassword,
        [Parameter()][string]$buildAgent_AgentName = "", 
        [Parameter()][string]$buildTools_installPath = "", 
        [Parameter()][string]$testAgent_installPath = "", 
        [Parameter()][string]$buildAgent_installDirectory = "",
        [Parameter()][string[]]$buildTools_componentsToInstall = @("Microsoft.VisualStudio.Workload.DataBuildTools", "Microsoft.VisualStudio.Workload.MSBuildTools", "Microsoft.VisualStudio.Workload.NetCoreBuildTools", "Microsoft.VisualStudio.Workload.NodeBuildTools", "Microsoft.VisualStudio.Workload.WebBuildTools"),
        [Parameter()][ValidateSet("32","64")][string]$buildAgent_bitness = "64"
    ) 
    Process {
        # see this for instructions on package parameters https://docs.microsoft.com/en-us/visualstudio/install/use-command-line-parameters-to-install-visual-studio?view=vs-2017
        # and this for workload/component IDs https://docs.microsoft.com/en-us/visualstudio/install/workload-component-id-vs-build-tools?vs-2017&view=vs-2017

        $ErrorActionPreference = "Stop"
        $InformationPreference = "Continue"

        choco install -y netfx-4.7.2-devpack

        if ($buildTools_installPath -eq "") { $installArgs = "" } else { $installArgs = "--installPath `"$buildTools_installPath`"" }
        $componentArgs = (($buildTools_componentsToInstall | % { "--add $($_);includeRecommended;includeOptional" }) -join " ")

        choco install -y visualstudio2017buildtools --package-parameters "$componentArgs $installArgs --passive --locale en-US"

        if ($testAgent_installPath -eq "") { $installArgs = "" } else { $installArgs = "--installPath `"$testAgent_installPath`"" }
        choco install -y visualstudio2017testagent --package-parameters "$installArgs --passive --locale en-US"


        # Download and Install Build Agent
        if ($buildAgent_AgentName -eq "") {
            $buildAgent_AgentName = "$($env:ComputerName)_$(generateShortGuid)"
        }

        if ($buildAgent_installDirectory -eq "") {
            $buildAgent_installDirectory = "C:\build-agents\"
        }
        $buildAgent_installPath = Join-Path $buildAgent_installDirectory $buildAgent_AgentName

        if (!(test-path $buildAgent_installPath)) { 
            mkdir $buildAgent_installPath | Out-Null
        }

        pushd $buildAgent_installPath

        if ($buildAgent_bitness -eq 32) { $agentDownloadUrl = "https://go.microsoft.com/fwlink/?linkid=2066763"; $agentFileName = "vsts-agent-win-x86-2.144.2.zip" } else { $agentDownloadUrl = "https://go.microsoft.com/fwlink/?linkid=2066756"; $agentFileName = "vsts-agent-win-x64-2.144.2.zip"  }

        if (test-path "$HOME\Downloads\$agentFileName") {
            remove-item "$HOME\Downloads\$agentFileName"
        }

        [Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
        iwr $agentDownloadUrl -outfile "$HOME\Downloads\$agentFileName"

        Add-Type -AssemblyName System.IO.Compression.FileSystem 
        [System.IO.Compression.ZipFile]::ExtractToDirectory("$HOME\Downloads\$agentFileName", "$PWD")

        .\config.cmd --unattended `
                    --url $buildAgent_Url `
                    --auth pat `
                    --token $buildAgent_PATToken `
                    --runAsService `
                    --agent $buildAgent_AgentName `
                    --windowsLogonAccount $buildAgent_LogonUsername `
                    --windowsLogonPassword $buildAgent_LogonPassword `
                    --replace
        popd
    }
}



<#
.SYNOPSIS
Uninstalls the Build Agent for Azure (or TFS)

.PARAMETER buildAgent_installPath
Directory where the Build Agent is installed

.PARAMETER buildAgent_PATToken
PAT token generated in Azure (or TFS) for administrative tasks

.PARAMETER tf_CollectionUrl
If the build agent was used with TF version control, the URL for the collection 

.PARAMETER tf_InstallPath
Location of the tf.exe, needed only if build agentw as used with TF version control

.EXAMPLE
Uninstall-BuildAgent -buildAgent_installPath "C:\build-agents\COMPUTERNAME_a12345" -buildAgent_PATToken "asdf1234" -tf_CollectionUrl "https://tfsinstance.yourdomain.com/tfs/collection" -tf_InstallPath "C:\VisualStudio2017BuildTools\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer"
#>
function Uninstall-BuildAgent {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)][string]$buildAgent_installPath,
        [Parameter(Mandatory = $true)][string]$buildAgent_PATToken,
        [Parameter()][string]$tf_CollectionUrl = "",
		[Parameter()][string]$tf_InstallPath = ""
    )
    Process {        
        $ErrorActionPreference = "Stop"
        $InformationPreference = "Continue"

        cd $buildAgent_installPath
        .\config.cmd remove --auth pat --token $buildAgent_PATToken

        # remove tf workspace bindings if present
        if (!($tf_CollectionUrl -eq "") -and (gci $buildAgent_installPath -r -directory -include "`$tf" -hidden).count -gt 0) {
            $workspaceOwner = "Project Collection Build Service"

            if (!($tf_InstallPath -eq "")) {
                $env:path += ";$tf_InstallPath"
            }

            gci $buildAgent_installPath -r -directory -include "`$tf" -hidden | % { 
                cd "$($_)`\.."
                
                if (!((tf workspaces /collection:$tf_CollectionUrl) | Select-String "No workspace matching" -Quiet)) {
                    $workspaces = (tf workspaces /collection:$tf_CollectionUrl) | Out-String

                    if ($workspaces -match "(.+)\s$([Regex]::Escape($workspaceOwner))\s") {
                        $workspaceName = $matches[1].TrimEnd()

                        tf workfold /unmap . /workspace:$workspaceName
                    }
                }
            }

            tf workspace /delete "$workspaceName;$workspaceOwner" /noprompt
        }

        cd C:\
        rm $buildAgent_installPath -r
    }
}