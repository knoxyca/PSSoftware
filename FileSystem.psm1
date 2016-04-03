function Compare-FilePath
{
	<#
	.SYNOPSIS
		This function checks the hash of 2 files see if they are the same
	.EXAMPLE
		PS> Compare-FilePath -ReferencePath 'C:\Windows\file.txt' -DifferencePath '\\COMPUTER\c$\Windows\file.txt'
	
		This example checks to see if the file C:\Windows\file.txt is exactly the same as the file \\COMPUTER\c$\Windows\file.txt
	.PARAMETER ReferencePath
		The first file path to compare
	.PARAMETER DifferencePath
		The second file path to compare
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
		[string]$ReferenceFilePath,
		
		[Parameter(Mandatory = $true)]
		[ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
		[string]$DifferenceFilePath
	)
	process
	{
		try
		{
			Write-Log -Message "$($MyInvocation.MyCommand) - BEGIN"
			$ReferenceHash = Get-MyFileHash -Path $ReferenceFilePath
			$DifferenceHash = Get-MyFileHash -Path $DifferenceFilePath
			if ($ReferenceHash.SHA256 -ne $DifferenceHash.SHA256)
			{
				$false
			}
			else
			{
				$true
			}
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
		}
		catch
		{
			Write-Log -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)" -LogLevel '3'
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
			$false
		}
	}
}

function Compare-FolderPath
{
	<#
	.SYNOPSIS
		This function checks all files inside of a folder against another folder to see if they are the same
	.EXAMPLE
		PS> Compare-FilePath -ReferencePath 'C:\Windows' -DifferencePath '\\COMPUTER\c$\Windows'
	
		This example checks to see if the contents in C:\Windows is exactly the same as the contents in \\COMPUTER\c$\Windows
	.PARAMETER ReferencePath
		The first folder path to compare
	.PARAMETER DifferencePath
		The second folder path to compare
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateScript({ Test-Path -Path $_ -PathType Container })]
		[string]$ReferenceFolderPath,
		
		[Parameter(Mandatory = $true)]
		[ValidateScript({ Test-Path -Path $_ -PathType Container })]
		[string]$DifferenceFolderPath
	)
	process
	{
		try
		{
			Write-Log -Message "$($MyInvocation.MyCommand) - BEGIN"
			$ReferenceFiles = Get-ChildItem -Path $ReferenceFolderPath -Recurse | where { !$_.PsIsContainer }
			$DifferenceFiles = Get-ChildItem -Path $DifferenceFolderPath -Recurse | where { !$_.PsIsContainer }
			if ($ReferenceFiles.Count -ne $DifferenceFiles.Count)
			{
				Write-Log -Message "Folder path '$ReferenceFolderPath' and '$DifferenceFolderPath' file counts are different" -LogLevel '2'
				$false
			}
			elseif (Compare-Object -ReferenceObject ($ReferenceFiles | Get-MyFileHash) -DifferenceObject ($DifferenceFiles | Get-MyFileHash))
			{
				Write-Log -Message "Folder path '$ReferenceFolderPath' and '$DifferenceFolderPath' file hashes are different" -LogLevel '2'
				$false
			}
			else
			{
				Write-Log -Message "Folder path '$ReferenceFolderPath' and '$DifferenceFolderPath' have equal contents"
				$true
			}
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
		}
		catch
		{
			Write-Log -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)" -LogLevel '3'
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
			$false
		}
	}
}

function Copy-FileWithHashCheck
{
	<#
	.SYNOPSIS
		This function copies a file and then verifies the copy was successful by comparing the source and destination
		file hash values.
	.EXAMPLE
		PS> Copy-FileWithHashCheck -SourceFilePath 'C:\Windows\file1.txt' -DestinationFolderPath '\\COMPUTER\c$\Windows\file2.txt'
	
		This example copied the file from C:\Windows\file1.txt to \\COMPUTER\c$\Windows and then checks the hash for the
		source file and destination file to ensure the copy was successful.
	.PARAMETER SourceFilePath
		The source file path
	.PARAMETER DestinationFolderPath
		The destination folder path
	.PARAMETER Force
		Overwrite the destination file if one exists
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, ValueFromPipeline = $True)]
		[Alias('Fullname')]
		[string]$SourceFilePath,
		
		[Parameter(Mandatory = $true)]
		[ValidateScript({ Test-Path -Path $_ -PathType Container })]
		[string]$DestinationFolderPath,
		
		[Parameter()]
		[switch]$Force
	)
	begin
	{
		Write-Log -Message "$($MyInvocation.MyCommand) - BEGIN"
		function Test-HashEqual ($FilePath1, $FilePath2)
		{
			$SourceHash = Get-MyFileHash -Path $FilePath1
			$DestHash = Get-MyFileHash -Path $FilePath2
			if ($SourceHash.SHA256 -ne $DestHash.SHA256)
			{
				$false
			}
			else
			{
				$true
			}
		}
	}
	process
	{
		try
		{
			$CopyParams = @{ 'Path' = $SourceFilePath; 'Destination' = $DestinationFolderPath }
			
			## If the file is already there, check to see if it's the one we're copying in the first place
			$DestFilePath = "$DestinationFolderPath\$($SourceFilePath | Split-Path -Leaf)"
			if (Test-Path -Path $DestFilePath -PathType 'Leaf')
			{
				if (Test-HashEqual -FilePath1 $SourceFilePath -FilePath2 $DestFilePath)
				{
					Write-Log -Message "The file $SourceFilePath is already in $DestinationFolderPath and is the same. No need to copy"
					return $true
				}
				elseif (!$Force.IsPresent)
				{
					throw "The file $SourceFilePath is already in $DestinationFolderPath but is not the same file being copied and -Force was not used."
				}
				else
				{
					$CopyParams.Force = $true
				}
			}
			Write-Log -Message "Copying [$($CopyParams.Path)] to [[$($CopyParams.Destination)]...."
			Copy-Item @CopyParams
			if (Test-HashEqual -FilePath1 $SourceFilePath -FilePath2 $DestFilePath)
			{
				Write-Log -Message "The file $SourceFilePath was successfully copied to $DestinationFolderPath."
				return $true
			}
			else
			{
				throw "Attempted to copy the file $SourceFilePath to $DestinationFolderPath but failed the hash check"
			}
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
		}
		catch
		{
			Write-Log -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)" -LogLevel '3'
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
			$false
		}
	}
}

function Find-InTextFile
{
	<#
	.SYNOPSIS
		Performs a find (or replace) on a string in a text file or files.
	.EXAMPLE
		PS> Find-InTextFile -FilePath 'C:\MyFile.txt' -Find 'water' -Replace 'wine'
	
		Replaces all instances of the string 'water' into the string 'wine' in
		'C:\MyFile.txt'.
	.EXAMPLE
		PS> Find-InTextFile -FilePath 'C:\MyFile.txt' -Find 'water'
	
		Finds all instances of the string 'water' in the file 'C:\MyFile.txt'.
	.PARAMETER FilePath
		The file path of the text file you'd like to perform a find/replace on.
	.PARAMETER Find
		The string you'd like to replace.
	.PARAMETER Replace
		The string you'd like to replace your 'Find' string with.
	.PARAMETER UseRegex
		Use this switch parameter if you're finding strings using regex else the Find string will
		be escaped from regex characters
	.PARAMETER NewFilePath
		If a new file with the replaced the string needs to be created instead of replacing
		the contents of the existing file use this param to create a new file.
	.PARAMETER Force
		If the NewFilePath param is used using this param will overwrite any file that
		exists in NewFilePath.
	#>
	[CmdletBinding(DefaultParameterSetName = 'NewFile')]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateScript({ Test-Path -Path $_ -PathType 'Leaf' })]
		[string[]]$FilePath,
		
		[Parameter(Mandatory = $true)]
		[string]$Find,
		
		[Parameter()]
		[string]$Replace,
		
		[Parameter()]
		[switch]$UseRegex,
		
		[Parameter(ParameterSetName = 'NewFile')]
		[ValidateScript({ Test-Path -Path ($_ | Split-Path -Parent) -PathType 'Container' })]
		[string]$NewFilePath,
		
		[Parameter(ParameterSetName = 'NewFile')]
		[switch]$Force
	)
	begin
	{
		$SystemTempFolderPath = Get-SystemTempFolderPath
		if (!$UseRegex.IsPresent)
		{
			$Find = [regex]::Escape($Find)
		}
	}
	process
	{
		try
		{
			Write-Log -Message "$($MyInvocation.MyCommand) - BEGIN"
			foreach ($File in $FilePath)
			{
				if ($Replace)
				{
					if ($NewFilePath)
					{
						if ((Test-Path -Path $NewFilePath -PathType 'Leaf') -and $Force.IsPresent)
						{
							Remove-Item -Path $NewFilePath -Force
							(Get-Content $File) -replace $Find, $Replace | Add-Content -Path $NewFilePath -Force
						}
						elseif ((Test-Path -Path $NewFilePath -PathType 'Leaf') -and !$Force.IsPresent)
						{
							Write-Warning "The file at '$NewFilePath' already exists and the -Force param was not used"
						}
						else
						{
							(Get-Content $File) -replace $Find, $Replace | Add-Content -Path $NewFilePath -Force
						}
					}
					else
					{
						(Get-Content $File) -replace $Find, $Replace | Add-Content -Path "$File.tmp" -Force
						Remove-Item -Path $File
						Rename-Item -Path "$File.tmp" -NewName $File
					}
				}
				else
				{
					Select-String -Path $File -Pattern $Find
				}
			}
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
		}
		catch
		{
			Write-Log -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)" -LogLevel '3'
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
			$false
		}
	}
}

function Register-File
{
	<#
	.SYNOPSIS
		A function that uses the utility regsvr32.exe utility to register a file
	.PARAMETER FilePath
		The file path
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[ValidateScript({ Test-Path -Path $_ -PathType 'Leaf' })]
		[string]$FilePath
	)
	process
	{
		try
		{
			Write-Log -Message "$($MyInvocation.MyCommand) - BEGIN"
			$Result = Start-Process -FilePath 'regsvr32.exe' -Args "/s `"$FilePath`"" -Wait -NoNewWindow -PassThru
			Wait-MyProcess -ProcessId $Result.Id
			Test-Error -SuccessString "Successfully registered file $FilePath"
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
		}
		catch
		{
			Write-Log -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)" -LogLevel '3'
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
			$false
		}
	}
}

function Remove-Folder
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Path
	)
	begin {
		$ErrorActionPreference = 'Stop'
	}
	process {
		try
		{
			foreach ($folder in $Path)
			{
				try
				{
					Write-Log -Message "Checking for $folder existence..."
					if (Test-Path $folder -PathType 'Container')
					{
						Write-Log -Message "Found folder $folder.  Attempting to remove..."
						Remove-Item $folder -Force -Recurse -ea 'Continue'
						if (!(Test-Path $folder -PathType 'Container'))
						{
							Write-Log -Message "Successfully removed $folder"
						}
						else
						{
							Write-Log -Message "Failed to remove $folder" -LogLevel '2'
						}
					}
					else
					{
						Write-Log -Message "$folder was not found..."
					}
					Get-Shortcut -MatchingTargetPath $folder -ErrorAction 'SilentlyContinue' | Remove-Item -ea 'Continue' -Force
				}
				catch
				{
					Write-Log -Message "Error occurred: '$($_.Exception.Message)' attempting to remove folder" -LogLevel '3'
				}
			}
		}
		catch
		{
			Write-Error $_.Exception.Message
		}
	}
}

function Set-MyFileSystemAcl
{
	<#
	.SYNOPSIS
		This function allows an easy method to set a file system access ACE
	.PARAMETER Path
	 	The file path of a file
	.PARAMETER Identity
		The security principal you'd like to set the ACE to.  This should be specified like
		DOMAIN\user or LOCALMACHINE\User.
	.PARAMETER Right
		One of many file system rights.  For a list http://msdn.microsoft.com/en-us/library/system.security.accesscontrol.filesystemrights(v=vs.110).aspx
	.PARAMETER InheritanceFlags
		The flags to set on how you'd like the object inheritance to be set.  Possible values are
		ContainerInherit, None or ObjectInherit. http://msdn.microsoft.com/en-us/library/system.security.accesscontrol.inheritanceflags(v=vs.110).aspx
	.PARAMETER PropagationFlags
		The flag that specifies on how you'd permission propagation to behave. Possible values are
		InheritOnly, None or NoPropagateInherit. http://msdn.microsoft.com/en-us/library/system.security.accesscontrol.propagationflags(v=vs.110).aspx
	.PARAMETER Type
		The type (Allow or Deny) of permissions to add. http://msdn.microsoft.com/en-us/library/w4ds5h86(v=vs.110).aspx
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateScript({ Test-Path -Path $_ })]
		[string]$Path,
		
		[Parameter(Mandatory = $true)]
		[string]$Identity,
		
		[Parameter(Mandatory = $true)]
		[string]$Right,
		
		[Parameter(Mandatory = $true)]
		[string]$InheritanceFlags,
		
		[Parameter(Mandatory = $true)]
		[string]$PropagationFlags,
		
		[Parameter(Mandatory = $true)]
		[string]$Type
	)
	
	process
	{
		try
		{
			Write-Log -Message "$($MyInvocation.MyCommand) - BEGIN"
			$Acl = (Get-Item $Path).GetAccessControl('Access')
			$Ar = New-Object System.Security.AccessControl.FileSystemAccessRule($Identity, $Right, $InheritanceFlags, $PropagationFlags, $Type)
			$Acl.SetAccessRule($Ar)
			Set-Acl $Path $Acl
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
		}
		catch
		{
			Write-Log -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)" -LogLevel '3'
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
			$false
		}
	}
}

function Get-FileVersion
{
	<#
	.SYNOPSIS
		This function finds the file version of a file.  This is useful for applications that don't
		register themselves properly with Windows Installer
	.PARAMETER FilePath
	 	A valid file path
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateScript({ Test-Path -Path $_ -PathType 'Leaf' })]
		[string]$FilePath
	)
	process
	{
		try
		{
			Write-Log -Message "$($MyInvocation.MyCommand) - BEGIN"
			(Get-ItemProperty -Path $FilePath).VersionInfo.FileVersion
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
		}
		catch
		{
			Write-Log -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)" -LogLevel '3'
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
			$false
		}
	}
}

function Get-MyFileHash
{
    <#
        .SYNOPSIS
            Calculates the hash on a given file based on the seleced hash algorithm.

        .DESCRIPTION
            Calculates the hash on a given file based on the seleced hash algorithm. Multiple hashing 
            algorithms can be used with this command.

        .PARAMETER Path
            File or files that will be scanned for hashes.

        .PARAMETER Algorithm
            The type of algorithm that will be used to determine the hash of a file or files.
            Default hash algorithm used is SHA256. More then 1 algorithm type can be used.
            
            Available hash algorithms:

            MD5
            SHA1
            SHA256 (Default)
            SHA384
            SHA512
            RIPEM160

        .NOTES
            Name: Get-FileHash
            Author: Boe Prox
            Created: 18 March 2013
            Modified: 28 Jan 2014
                1.1 - Fixed bug with incorrect hash when using multiple algorithms

        .OUTPUTS
            System.IO.FileInfo.Hash

        .EXAMPLE
            Get-FileHash -Path Test2.txt
            Path                             SHA256
            ----                             ------
            C:\users\prox\desktop\TEST2.txt 5f8c58306e46b23ef45889494e991d6fc9244e5d78bc093f1712b0ce671acc15      
            
            Description
            -----------
            Displays the SHA256 hash for the text file.   

        .EXAMPLE
            Get-FileHash -Path .\TEST2.txt -Algorithm MD5,SHA256,RIPEMD160 | Format-List
            Path      : C:\users\prox\desktop\TEST2.txt
            MD5       : cb8e60205f5e8cae268af2b47a8e5a13
            SHA256    : 5f8c58306e46b23ef45889494e991d6fc9244e5d78bc093f1712b0ce671acc15
            RIPEMD160 : e64d1fa7b058e607319133b2aa4f69352a3fcbc3

            Description
            -----------
            Displays MD5,SHA256 and RIPEMD160 hashes for the text file.

        .EXAMPLE
            Get-ChildItem -Filter *.exe | Get-FileHash -Algorithm MD5
            Path                               MD5
            ----                               ---
            C:\users\prox\desktop\handle.exe  50c128c5b28237b3a01afbdf0e546245
            C:\users\prox\desktop\PortQry.exe c6ac67f4076ca431acc575912c194245
            C:\users\prox\desktop\procexp.exe b4caa7f3d726120e1b835d52fe358d3f
            C:\users\prox\desktop\Procmon.exe 9c85f494132cc6027762d8ddf1dd5a12
            C:\users\prox\desktop\PsExec.exe  aeee996fd3484f28e5cd85fe26b6bdcd
            C:\users\prox\desktop\pskill.exe  b5891462c9ca5bddfe63d3bae3c14e0b
            C:\users\prox\desktop\Tcpview.exe 485bc6763729511dcfd52ccb008f5c59

            Description
            -----------
            Uses pipeline input from Get-ChildItem to get MD5 hashes of executables.

    #>
	[CmdletBinding()]
	Param (
		[Parameter(Position = 0, Mandatory = $true, ValueFromPipelineByPropertyName = $true, ValueFromPipeline = $True)]
		[Alias("PSPath", "FullName")]
		[string[]]$Path,
		
		[Parameter(Position = 1)]
		[ValidateSet("MD5", "SHA1", "SHA256", "SHA384", "SHA512", "RIPEMD160")]
		[string[]]$Algorithm = "SHA256"
	)
	Process
	{
		Write-Log -Message "$($MyInvocation.MyCommand) - BEGIN"
		ForEach ($item in $Path)
		{
			try
			{
				$item = (Resolve-Path $item).ProviderPath
				If (-Not ([uri]$item).IsAbsoluteUri)
				{
					Write-Verbose ("{0} is not a full path, using current directory: {1}" -f $item, $pwd)
					$item = (Join-Path $pwd ($item -replace "\.\\", ""))
				}
				If (Test-Path $item -Type Container)
				{
					Write-Warning ("Cannot calculate hash for directory: {0}" -f $item)
					Return
				}
				$object = New-Object PSObject -Property @{
					Path = $item
				}
				#Open the Stream
				$stream = ([IO.StreamReader]$item).BaseStream
				foreach ($Type in $Algorithm)
				{
					[string]$hash = -join ([Security.Cryptography.HashAlgorithm]::Create($Type).ComputeHash($stream) |
					ForEach { "{0:x2}" -f $_ })
					$null = $stream.Seek(0, 0)
					#If multiple algorithms are used, then they will be added to existing object
					$object = Add-Member -InputObject $Object -MemberType NoteProperty -Name $Type -Value $Hash -PassThru
				}
				$object.pstypenames.insert(0, 'System.IO.FileInfo.Hash')
				#Output an object with the hash, algorithm and path
				Write-Output $object
				
				#Close the stream
				$stream.Close()
				Write-Log -Message "$($MyInvocation.MyCommand) - END"
			}
			catch
			{
				Write-Log -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)" -LogLevel '3'
				Write-Log -Message "$($MyInvocation.MyCommand) - END"
				$false
			}
		}
	}
}