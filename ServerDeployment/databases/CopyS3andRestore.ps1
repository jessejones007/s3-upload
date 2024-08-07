# The S3 event notification passes the bucket name and key (path to file) to Systems Manager, which will pass it here
param(
    [string]$backupKey,
    [string]$bucketName
)

$localFolderPath = "U:\Backup\" # The \ at the end is necessary
$localFilePath = $localFolderPath + $backupKey # Should be U:\Backup\prefix\fileName

# Insert regular expression to get the correct server name from the passed key
# Key Format --> \\non-prod-db-backups.nt.lab.com\backups\SERVERNAME\DATABASENAME\FULL\BACKUPFILE.bak
Write-Host $backupKey
$splitBackupkey = $backupKey -split '/'
$serverName = $splitBackupkey[2]   # Change to 1 if in the testing bucket
$databaseName = $splitBackupkey[3] # Change to 2 if in the testing bucket
Write-Host $serverName
Write-Host $databaseName

# Set up ability to use Get-SQLInstance --> Relocate to user data
Install-PackageProvider -Name NuGet -Force -Scope CurrentUser

Install-Module -Name SqlServer -Force -Scope CurrentUser -AllowClobber
Import-Module SqlServer

$sqlServerInstance = Get-SQLInstance -ServerInstance "localhost"

# Copy from bucket to local machine 
# Needs to grab the latest backup starting with the server name
function Copy-S3File{
    Write-Host "Copying file from S3"
    try{
        Copy-S3Object -BucketName $bucketName -Key $backupKey -LocalFolder $localFolderPath
        Write-Host "File copied to $localFolderPath"
    } catch {
        Write-Error "Error copying file from S3: $_"
        exit 1
    }
}

# Restores the Database
function Restore-DB{
    Write-Host "Restoring Database"

    try{
        # Relocating the data and log files to the corresponding drives
        $RelocateData = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile("${databaseName}", "F:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\${databaseName}.mdf")
        $RelocateLog = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile("${databaseName}_Log", "L:\SQLLogs\${databaseName}.ldf")
        # Actual restore
        Restore-SqlDatabase -ServerInstance "localhost" -Database $databaseName -BackupFile $localFilePath -RelocateFile @($RelocateData,$RelocateLog) -ErrorAction Stop
        Write-Host "Database restored successfully"
    } catch {
        Write-Error "Error restoring database: $_"
        exit 1
    }
}

Copy-S3File
Restore-DB