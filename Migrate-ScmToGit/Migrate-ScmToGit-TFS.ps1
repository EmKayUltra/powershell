function setupScm_TFS([string]$tfsCollectionUrl, [string]$tfsSource, [string]$startingChangesetID)
{
	if (($startingChangesetID -eq "") -or ($startingChangesetID -eq $null)) { throw "Starting Changeset ID not provided, and TFS requires it." }

	if ((get-command "tf.exe" -erroraction silentlycontinue) -eq $null) {
		if (Test-Path "C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer") {
			$env:Path += ";C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer" # tf 2017
		}
		elseif (Test-Path "C:\Program Files (x86)\Microsoft Visual Studio\2019\Professional\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer") {
			$env:Path += ";C:\Program Files (x86)\Microsoft Visual Studio\2019\Professional\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer" # tf 2019
		}
		else {
			throw "No tf.exe found on machine."
		}
	}
	$workspaceName = "git-migrate"

    if (!((tf workspaces "$($workspaceName)" /collection:$tfsCollectionUrl) | Select-String "No workspace matching" -Quiet)) {
        write-output "Existing TFS workspace found for $workspaceName. Skipping creation."
    }
    else {
        write-output "Creating TFS workspace $workspaceName"
        (tf workspace /new "$($workspaceName)" /collection:$tfsCollectionUrl) | Write-Verbose
	}

	if ((tf workfold /workspace:"$($workspaceName)" /collection:$tfsCollectionUrl) | Select-String $tfsSource -SimpleMatch -Quiet) {
        write-output "TFS local branch already found. Skipping mapping.";
    }
    else {
        write-output "Mapping $tfsSource.";
        (tf workfold $tfsSource . /map /workspace:"$($workspaceName)" /collection:$tfsCollectionUrl /noprompt) | Write-Verbose # create tfs mapping for new version in new workspace
    }
}

function getChangesetHistory_TFS([string]$startingChangesetID)
{
	$changesets = (tf history . /r /noprompt /V:C$($startingChangesetID)~T /sort:ascending) # in order oldest->youngest, 2745 is the first changeset we want to consider
	$numberIndex = 0
	$commentIndex = $changesets[0].indexof("Comment")
	$userIndex = $changesets[0].indexof("User")
	$userLength = $changesets[0].indexof("Date") - $userIndex
	$changesetObjs = $changesets | % { [pscustomobject]@{Changeset=$_.substring($numberIndex, $_.indexof(" "));Comment=$_.substring($commentIndex).TrimEnd();User=$_.substring($userIndex, $userLength).TrimEnd();} } | Select -skip 2	

	return $changesetObjs
}

function getChangesetLocally_TFS([string]$changesetID)
{
	tf get /V:C$($changesetID)
}

function cleanupScm_TFS() 
{
	tf label "migrated to git" . /recursive
	tf workfold /unmap .
	tf workspace /delete "git-migrate"
}