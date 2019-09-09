# README

## SCM Specific Implementations
To get this to work for a new SCM, you must:
1. create a new file named Migrate-ScmToGit-SCMTYPE.ps1 where SCMTYPE is an abbreviation of your SCM (e.g. "TFS") 
2. implement the functions specified in the Migrate-ScmToGit.ps1 file, namely:
    * function setupScm_SCMTYPE([string]$scmPath, [string]$startingChangesetID) 
    * function getChangesetHistoryFromScm_SCMTYPE([string]$startingChangesetID)
    * function getChangesetLocallyFromScm_SCMTYPE([string]$changesetID)
    * function cleanupScm_SCMTYPE()

You can find out more about these functions within the Migrate-ScmToGit.ps1 file


## Run Example
`> . .\Migrate-ScmToGit.ps1`

`> cd "C:\code\utilities" # Path to empty directory where git repo will be made`

`> Migrate-ScmToGit "TFS" "$/TFSProjectName/Utilities" "https://tfsinstance.yourdomain.com/tfs/collection/TFSProjectName/_git/Utilities" "961"`