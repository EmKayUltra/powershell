#region Required SCM functions

<#
.SYNOPSIS
Sets up your current directory for SCM operations

.DESCRIPTION
After this function runs, the current directory should be setup as a repository pointing to trunk in your SCM and ready for version control operations against your SCM

.PARAMETER scmUrl
Url to your SCM

.PARAMETER scmPath
Path used by your SCM to identify the path to the appropriate trunk repository (e.g., for TFS it would be "$/BAC/Applications/EIBilling/trunk")

.PARAMETER scmType
SCM abbreviation (e.g. "TFS", "SVN")

.NOTES
you will need to implement an SCM-specific implementation with an appropriate name with the same function signature without scmType (e.g. for "TFS", setupScm_TFS $scmPath $startingChangesetID)
#>
function setupScm([string]$scmUrl, [string]$scmPath, [string]$startingChangesetID, [string]$scmType) 
{
    invoke-expression "setupScm_$scmType $scmUrl $scmPath $startingChangesetID"
}


<#
.SYNOPSIS
Converts SCM changesets into consistent Changeset Objects

.DESCRIPTION
This is essentially a mapping function, converts history of changesets into array of pscustomobjects of type
	{ 
		Changeset # unique identifier of changeset
		Comment # any comment associated with the changeset
		User # the user who performed the initial changeset
	}

.PARAMETER startingChangesetID
number of the first changeset to start the migration from; typically, the very first changeset in your commit history

.PARAMETER scmType
SCM abbreviation (e.g. "TFS", "SVN")

.NOTES
you will need to implement an SCM-specific implementation with an appropriate name with the same function signature without scmType (e.g. for "TFS", getChangesetHistoryFromScm_TFS $startingChangesetID)
#>
function getChangesetHistoryFromScm([string]$startingChangesetID, [string]$scmType)
{
	invoke-expression "getChangesetHistory_$scmType $startingChangesetID"
}


<#
.SYNOPSIS
Downloads the changeset from the remote repository locally

.PARAMETER changesetID
Unique identifier of the changeset to be downloaded

.PARAMETER scmType
SCM abbreviation (e.g. "TFS", "SVN")

.NOTES
you will need to implement an SCM-specific implementation with an appropriate name with the same function signature without scmType (e.g. for "TFS", getChangesetLocallyFromScm_TFS $changesetID)
#>
function getChangesetLocallyFromScm([string]$changesetID, [string]$scmType)
{
	invoke-expression "getChangesetLocally_$scmType $changesetID"
}


<#
.SYNOPSIS
Post-merge clean up

.DESCRIPTION
Cleans up the machine/repository in whatever way is appropriate for the specific SCM

.PARAMETER scmType
SCM abbreviation (e.g. "TFS", "SVN")

.NOTES
you will need to implement an SCM-specific implementation with an appropriate name with the same function signature without scmType (e.g. for "TFS", "cleanupScm_TFS")
#>
function cleanupScm([string]$scmType)
{
	invoke-expression "cleanupScm_$scmType"
}

#endregion Required SCM functions



#beginregion internal

function loadScmImplementations() 
{
	gci Migrate-ScmToGit-*.ps1 | % { . $_ }
}

function gitSetup() 
{
	if (test-path ".git") {
		throw "Git repository already found in this directory.  Please use an empty directory."
	}

	if ((get-command "git.exe" -erroraction silentlycontinue) -eq $null) {
		if (test-path "C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\Git\cmd") {
			$env:path += ";C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\Git\cmd"
		}
		elseif (test-path "C:\Program Files (x86)\Microsoft Visual Studio\2019\Professional\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\Git\cmd") {
			$env:path += ";C:\Program Files (x86)\Microsoft Visual Studio\2019\Professional\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\Git\cmd"
		}
		else {
			throw "No git.exe found on machine."
		}
	}

	git init

	".svn/`n`$tf/`n.vs/`nbin/`nobj/" | out-file ".gitignore" -Encoding UTF8
	git add .gitignore
	git commit -m "adding gitignore for migration"
}

function gitChangeset($changesetObj, [string]$scmType)
{
	write-output "gitting changeset $($changesetObj.Changeset)"
	
	getChangesetLocallyFromScm $changesetObj.Changeset $scmType
	
	git add --all #git stage everything
	git commit -m "MIGRATION: changeset $($changesetObj.Changeset) ; $($changesetObj.User) ; $($changesetObj.Comment)" #git commit everything
	git checkout master
	git merge scm-migration
	git checkout scm-migration
}

#endregion internal



<#
.SYNOPSIS
Migrates a repository in a non-git SCM into a git repository

.DESCRIPTION
Starting with an empty directory, migrates the SCM SOURCE into a GIT DESTINATION, preserving changeset history

.PARAMETER scmType
Abbreviated name of SCM (e.g. "TFS", "SVN")

.PARAMETER scmUrl
Url to your SCM

.PARAMETER scmSourcePath
Path used by your SCM to identify the path to the appropriate trunk repository (e.g., for TFS it would be "$/BAC/Applications/EIBilling/trunk")

.PARAMETER gitDestinationRepoUrl
URL of Git remote repository to push changes to

.PARAMETER startingChangesetID
The unique identifier of the first changeset you want included in the migration, OPTIONAL but a specific SCM implementation might require it

.PARAMETER gitMigrationBranchName
Name of branch created in Git for migration, defaults to "scm-migration" 

.EXAMPLE
Migrate-ScmToGit "TFS" "https://tfsinstance.yourdomain.com/tfs/collection" "$/ProjectName/Utilities/trunk" "https://tfsinstance.yourdomain.com/tfs/collection/BAC/_git/Utilities" -startingChangesetID "1"

.NOTES
General notes
#>
function Migrate-ScmToGit {
    [CmdletBinding()]
    Param (
		[Parameter(Mandatory = $true)][string]$scmType, 
		[Parameter(Mandatory = $true)][string]$scmUrl, 
		[Parameter(Mandatory = $true)][string]$scmSourcePath, 
		[Parameter(Mandatory = $true)][string]$gitDestinationRepoUrl, 
		[string]$startingChangesetID = "",
		[string]$gitMigrationBranchName = "scm-migration"
    ) 
    Process {
        $ErrorActionPreference = "Stop"
        $InformationPreference = "Continue"
        
		loadScmImplementations
		setupScm $scmUrl $scmSourcePath $startingChangesetID $scmType 
		gitSetup

		git checkout -b $gitMigrationBranchName
		(getChangesetHistoryFromScm $startingChangesetID $scmType) | % { gitChangeset $_ $scmType }

		git checkout master
		git remote add origin $gitDestinationRepoUrl
		git push --all origin
		
		cleanupScm $scmType
			
		git push --set-upstream origin $gitMigrationBranchName
	}
}