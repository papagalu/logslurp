#!/usr/bin/pwsh
param(
    [String] $WinUser,
    [String] $WinPass,
    [String] $OutputFolder
)

function Main {
    $lockedFiles = "kubelet.err.log", "kubelet.log", "kubeproxy.log", "kubeproxy.err.log"

    $passwd = ConvertTo-SecureString $WinPass -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential ($WinUser, $passwd) 

    $nodes = kubectl get node -o json | ConvertFrom-Json

    foreach ($node in $nodes.items) {
        if ($node.metadata.labels.'beta.kubernetes.io/os' -eq 'windows') {
            Add-Member -InputObject $node -MemberType NoteProperty -Name "PSSession" `
                -Value (New-PSSession -ComputerName $node.status.nodeInfo.machineID `
                -Credential $cred -UseSSL -Authentication basic)

            Write-Host "Connected to " + $node.status.nodeInfo.machineID
            # Write-Host Logs:
            $zipName = "$($node.status.nodeInfo.machineID)-$(get-date -format 'yyyyMMdd-hhmmss')_logs.zip"
            $remoteZipPath = Invoke-Command -Session $node.PSSession { 
                $paths = Get-ChildItem C:\k\*.log -Exclude $using:lockedFiles
                $paths += $using:lockedFiles | Foreach-Object { Copy-Item "c:\k\$node" . -Passthru }
                # docker ps
                docker ps  > "docker_ps.txt"
                $paths += "docker_ps.txt"
                Compress-Archive -Path $paths -DestinationPath $using:zipName
                Get-ChildItem $using:zipName
            } 
            Copy-Item -FromSession $node.PSSession $remoteZipPath -Destination $OutputFolder
        }
    }
}

Main
