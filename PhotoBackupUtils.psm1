# Import-Module ExifDateTime

<#
    .Synopsis
       Copies files, dynamically renaming them to avoid namespace collisions.
    .Description
       This function copies or moves files into a destination folder, using a numbering system 
       to avoid namespace collisions within that folder. In the event of a namespace collision 
       "_X" is appended to the name of the file in the destination folder, where X is an integer.
       X starts as 1 and is incremented until the new name is unique in the destination folder. 
       
       N.B. X does not have leading zeros. 
    .Parameter Path
       The file to copy/move. Supports wildcards. 
    .Parameter Dest
       The directory to copy/move the file or files into. Must be a literal path (i.e. no 
       wildcards). 
    .Parameter KeepNumbering 
       Switch parameter, if specified any existing _Y on the original file is stripped from the 
       copy, where Y is an integer between 0 and 99. This is to prevent file names such as 
       "File_1_1.txt". 
       
       N.B. that this only matches 1- or 2-digit values of Y. 
    .Parameter NewTimestamps 
       Switch parameter, if specified the copied files will not necessarily have the same 
       CreationTime, LastAccessTime, LastWriteTime, Attributes or permissions as the original 
       files. 
       
       N.B. This parameter does nothing If Move is specified.       
    .Parameter Move 
       Switch parameter, if specified the files are moved rather than copied. 
    .Parameter PassThru
       Switch parameter, if specified the paths of the copies are written to the pipeline (as a 
       System.IO.FileInfo).
    .Example
       Copy-FileWithDynamicRename '.\dir1\*' '.\dir2\'
       Copy all top-level files from dir1 to dir3, renaming the files as needed. 
    .Example
       Copy-FileWithDynamicRename '.\dir1\img1.JPG' '.\dir2\' -Verbose
       Copy img1.JPG to dir3, renaming the file as needed. 
    .Example
       Copy-FileWithDynamicRename '.\dir1\img1.jpg' '.\dir2\' -Move
       Move img1.JPG to dir3, renaming the file as needed. 
    .Example
       gci '.\dir1\' -File -Recurse | Copy-FileWithDynamicRename -Dest '.\dir3' -Verbose
       Copy all child items of dir1 to dir3, renaming as necessary. 
    .Outputs
       [System.IO.FileInfo]
       If -PassThru is specified, the function returns the new files in the destination 
       folder.
    .Notes
       This function was intended to create backup files in a flat directory, specifically to
       add files to the 'iCloud For Windows' Photos folder. 

       robocopy is an existing cmdlet that can copy files and retain their timestamps, but it
       does not prevent namespace collisions, necessiating implementing this function. 
    .Functionality
       Copies or moves files into a flat directory, dynamically appending an integer counter to 
       base names to avoid namespace collisions.
    #>
function Copy-FileWithDynamicRename {
    [OutputType([System.IO.FileInfo])]

    param (
        [Parameter(Mandatory = $True, ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True)]
        [String]
        [Alias('FullName', 'FileName')]
        $Path,
        
        [Parameter(Mandatory = $True)]
        [System.IO.DirectoryInfo]
        [Alias('Destination')]
        $Dest,
        
        [Switch]$KeepNumbering,
        
        [Switch]$NewTimestamps,
        
        [Switch]$Move, 

        [Switch]$PassThru
    )

    Process {
        # Start of code adapted from [ExifDateTime](https://github.com/chestercodes/ExifDateTime). Accessed 29/12/23. 
        # Cater For arrays of filenames and wild-cards by using Resolve-Path
        Write-Verbose "Processing input item '$Path'"
            
        If ($NewTimestamps -and $Move) {
            Write-Warning "-Move and -NewTimestamps do not work together. The moved file(s) will retain their original timestamps."
        }

        # Keep only the resolved paths that lead to files (not directories) 
        $FileItems = Resolve-Path -Path $Path -ErrorAction SilentlyContinue -ErrorVariable ResolveError | 
        ForEach-Object { Get-Item $_.Path } | 
        Where-Object { $_.PSIsContainer -eq $False }
        If ($ResolveError) {
            Write-Warning "Bad path '$Path' ($($ResolveError[0].CategoryInfo.Category))"
        }

        # End of code adapted from ExifDateTime

        ForEach ($FileItem in $FileItems) {
            Write-Debug $FileItem

            $BaseName = $FileItem.BaseName
            $Extension = $FileItem.Extension
            $Counter = 0 

            If (!$KeepNumbering) {
                # Remove existing _X, in case the base name is available 
                $BaseName = $BaseName -replace '_\d{0,2}$', ''
            }

            # Construct the first potential path to the copy 
            $NewName = "$BaseName$Extension"
            $CopyPath = "$($Dest.FullName)\$NewName" -replace '\\\\', '\'

            # Add _X to the file name and incremenet X until no name conflict at destination 
            # _X is not added If the base name is available at the destination 
            While ([System.IO.File]::Exists($CopyPath)) {
                $Counter++
                $NewName = "${BaseName}_$Counter$Extension"
                $CopyPath = "$($Dest.FullName)\$NewName" -replace '\\\\', '\'
            } 

            # Create placeholder copy object 
            $Copy = [System.IO.FileInfo]$CopyPath

            If (!$Move) {
                # Start of code taken from [Nick Petrovic on Stack Overflow](https://stackoverflow.com/a/21594427). Accessed 15/12/23. 
                # Copy the file
                Copy-Item $FileItem.FullName -Destination $Copy.FullName

                # Make sure file was copied and exists before copying over properties/attributes
                If ($Copy.Exists -and !$NewTimestamps) {
                    $Copy.CreationTime = $FileItem.CreationTime
                    $Copy.LastAccessTime = $FileItem.LastAccessTime
                    $Copy.LastWriteTime = $FileItem.LastWriteTime
                    $Copy.Attributes = $FileItem.Attributes
                    $Copy.SetAccessControl($FileItem.GetAccessControl())
                }

                # End of code by Nick Petrovic. 

                Write-Verbose "'$FileItem' copied to '$Copy'"
            }
            Else {
                Move-Item -Path $FileItem -Destination $Copy
                Write-Verbose "'$FileItem' moved to '$Copy'"
            }

            If ($PassThru) {
                $Copy     
            }
        }
    }
}
Set-Alias cpwr Copy-FileWithDynamicRename # CoPy With Rename

<#
    .Synopsis
       Removes duplicate files from a directory, identified as having matching names and 
       timestamps.
    .Description
       This function identifies files that could be duplicates of other files based on having a
       common base name, with the duplicate having an appended _X (where X is a one- or two-
       digit integer). If two files that match names in this way also have the same LastWriteTime
       or CreationTime then the one with a suffix is considered a duplicate and is deleted (or 
       moved to a different folder).        
    .Parameter Path
       The directory or directories to remove duplicates from. Supports wildcards. 
    .Parameter Keep 
       Switch parameter, if specified duplicates are added to a Duplicates subdirectory instead 
       of deleted. The Duplicates subdirectory will be created in the Path directory (If it does
       not already exist).      

       N.B. Since the Duplicates subdirectory is shared between other subdirectories of its 
       parent, namespace collisions could occur and are not handled by this function; Move-Item
       will throw an error. 
    .Parameter PassThru
       Switch parameter, if specified the directories from which the duplicates were removed are
       returned.
    .Example
       Remove-Duplicates '.\dir1\' 
       Deletes all duplicates in dir1. 
    .Example
       Remove-Duplicates '.\dir1\' -Keep 
       Moves all duplicate files in dir1 to dir1\Duplicates\. 
       N.B. The Duplicates subdirectory will be shared between all subdirectories of dir1. 
    .Example
       Remove-Duplicates '.\dir*\' -Keep 
       Moves all duplicate files in directories matching .\dir*\ into .\dir*\Duplicates.
       
       N.B. Each directory matching .\dir*\ will have its own Duplicates subdirectory (which is 
       shared between the other subdirectories of its parent). 
    .Outputs
       [System.IO.FileInfo]
       If -PassThru is specified, the function the new files in the destination folder.
    .Notes
       This function was written to detect and resolve duplicate photos introduced by a specific
       human error and will be of limited direct use in most situations.  
    .Functionality
       Attempts to identify duplicate files based on their names and timestamps, and deletes or 
       moves identified duplicates. 
    #>
function Remove-Duplicates {
    param(
        [Parameter(Mandatory = $True)][String]$Path,
        [Switch]$Keep,
        [Switch]$PassThru
    )

    Process {
        # Start of code adapted from [ExifDateTime](https://github.com/chestercodes/ExifDateTime). Accessed 29/12/23. 
        # Cater For arrays of filenames and wild-cards by using Resolve-Path
        Write-Verbose "Processing input item '$Path'"
            
        If ($NewTimestamps -and $Move) {
            Write-Warning "-Move and -NewTimestamps do not work together. The moved file(s) will retain their original timestamps."
        }

        # Keep only the resolved paths that lead to directories 
        $Dirs = Resolve-Path -Path $Path -ErrorAction SilentlyContinue -ErrorVariable ResolveError | 
        ForEach-Object { Get-Item $_.Path } | 
        Where-Object { $_.PSIsContainer -eq $True }
        If ($ResolveError) {
            Write-Warning "Bad path '$Path' ($($ResolveError[0].CategoryInfo.Category))"
        }

        # End of code adapted from ExifDateTime

        ForEach ($Dir in $Dirs) {
            If ($Keep) {
                $DuplicateDir = New-Item -Path $Dir -Name 'Duplicates' -ItemType 'directory' -Force
            }

            $Files = Get-ChildItem $Dir -Recurse -File 
            $SuffixPattern = '_\d{1,2}$'
 
            ForEach ($File in $Files) {
                $Extension = $File.Extension
                $BaseName = $File.BaseName
                # While file base name ends in _X, where 0 <= X <= 99
                While (($BaseName -match $SuffixPattern)) {

                    # Remove (one layer of) _X from base name 
                    $NoSuffixBaseName = $BaseName -replace $SuffixPattern, ''
                    $NoSuffixFile = [IO.FileInfo]("$($File.DirectoryName)\$NoSuffixBaseName$Extension")
            
                    If ($NoSuffixFile.Exists) {
                        Write-Debug "Potential duplicate $File and $NoSuffixFile" 

                        $IsDuplicate = ($NoSuffixFile.LastWriteTime -eq $File.LastWriteTime) -or ($NoSuffixFile.CreationTime -eq $File.CreationTime)
                        If ($IsDuplicate) {
                            If (!$Keep) {
                                Write-Verbose "Removing $File"
                                Remove-Item -LiteralPath $File.FullName
                            }
                            Else {
                                Write-Verbose "Moving $File to $DuplicateDir\$($File.Name)"
                                Move-Item -Path $File.FullName -Destination "$DuplicateDir\$($File.Name)"
                            }
                        }
                    }

                    $BaseName = $NoSuffixBaseName
                }
            } 

            If ($PassThru) {
                $Dir
            }
        }
    }
}
Set-Alias rmvdup Remove-Duplicates # ReMoVe DUPlicates 

<#
    .Synopsis
       Attempts to find and return the date taken of a file. 
    .Description
       This function iterates over the details of a file's parent folder to try to find a date
       taken field. If it can do so, and the file has a non-null value corresponding to that 
       attribute index then it is returned as a datetime object. For some reason this does not 
       is only as fine-grained as minutes, and does not include seconds. 

       If a date taken cannot be obtained then the function returns the date created by 
       default, and can instead be made to return the last write time (i.e. date modified). 
       Date taken is part of the Exif standard, and as such most files do not have a date 
       taken. 
    .Parameter Path
       The file or files to get the date taken of. Supports wildcards. 
    .Parameter DefaultToLastWrite
       Switch parameter, if specified then the date modified is returned instead of the date
       created for files with no date taken.        
    .Example
       Get-DateTaken '.\dir1\*.jpg' 
       Get the date taken of all the jpgs in dir1. 
    .Example
       Get-DateTaken '.\dir1\*' 
       Get the date taken of all the files in dir1. Non-Exif files will likely not have a date
       taken, and their date created will be returned instead. 
    .Example
       Get-DateTaken '.\dir1\*' -lw
       Get the date taken of all the files in dir1. Non-Exif files will likely not have a date
       taken, and their date modified will be returned instead. 
    .Outputs
       [DateTime]
       The date taken (or created, or modified) of the passed file(s).
    .Notes
       I created this before finding the [ExifDateTime module]
       (https://github.com/chestercodes/ExifDateTime), but still consider this function useful
       because unlike ExifDateTime it can fall back to date created or date modified. 

       I suggest using ExifDateTime.Get-ExifDateTaken in a try catch block, and calling 
       Get-DateTaken within the catch block. ExifDateTime.Get-ExifDateTaken includes seconds 
       in its output, making it preferable.  
    .Functionality
       Retrieves date taken information as a DateTime object. For files without a date taken
       attribute, returns the date created or date modified. Dates returned are precise only 
       to the minute, and are missing the seconds. 
    #>
function Get-DateTaken {
    [OutputType([datetime])]
    param (
        [Parameter(Mandatory = $True, ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True)]
        [String]
        [Alias('FullName', 'FileName')]
        $Path,        
        
        [Switch][Alias('lw')]$DefaultToLastWrite
    )

    Process {

        # Start of code adapted from [ExifDateTime](https://github.com/chestercodes/ExifDateTime). Accessed 29/12/23. 
        # Cater For arrays of filenames and wild-cards by using Resolve-Path
        Write-Verbose "Processing input item '$Path'"
            
        If ($NewTimestamps -and $Move) {
            Write-Warning "-Move and -NewTimestamps do not work together. The moved file(s) will retain their original timestamps."
        }

        # Keep only the resolved paths that lead to files 
        $FilePaths = Resolve-Path -Path $Path -ErrorAction SilentlyContinue -ErrorVariable ResolveError | 
        ForEach-Object { Get-Item $_.Path } | 
        Where-Object { $_.PSIsContainer -eq $False }
        If ($ResolveError) {
            Write-Warning "Bad path '$Path' ($($ResolveError[0].CategoryInfo.Category))"
        }

        # End of code adapted from ExifDateTime

        ForEach ($FilePath in $FilePaths) {
            # The following code is adapted from [Andrew Cleveland on Stack Overflow](https://stackoverflow.com/a/8626010). Accessed 09/01/24. 

            $ShellObject = New-Object -ComObject Shell.Application
            $DirectoryObject = $ShellObject.NameSpace( $FilePath.Directory.FullName )
            $FileObject = $DirectoryObject.ParseName( $FilePath.Name )

            $CreatedLabel = 'Date created'
            $LastWriteLabel = 'Date modified'
            $TakenLabel = 'Date taken'
    
            $DateCreated = $null
            $DateModified = $null
            $DateTaken = $null

            For (
                $Index = 1;
                $DirectoryObject.GetDetailsOf( $DirectoryObject.Items, $Index ) -ne $TakenLabel;
                ++$Index ) { 
                If ($DirectoryObject.GetDetailsOf( $DirectoryObject.Items, $Index ) -eq $CreatedLabel) {
                    $DateCreated = $DirectoryObject.GetDetailsOf( $FileObject, $Index )
                }
                ElseIf ($DirectoryObject.GetDetailsOf( $DirectoryObject.Items, $Index ) -eq $LastWriteLabel) {
                    $DateModified = $DirectoryObject.GetDetailsOf( $FileObject, $Index )
                }
            }
   
            $DateTaken = $DirectoryObject.GetDetailsOf( $FileObject, $Index )
    
            # End of adapted code 

            If (("" -eq $DateTaken) -or ($null -eq $DateTaken)) {
                # No date taken was found: default to date created or modified
                If ($DefaultToLastWrite) {
                    Write-Output ([DateTime]::parse($DateModified))
                }
                Else {
                    Write-Output ([DateTime]::parse($DateCreated))
                }
       
            }
            Else {
                # Date taken was found 
                # Clean weird silent characters out of string before parsing to datetime
                $CleanDateTaken = ""
                For ($i = 0;
                    $i -lt 21; 
                    $i++) {
                    If ( $DateTaken[$i] -match '[\d\s/:]') {
                        $CleanDateTaken = ($CleanDateTaken, $DateTaken[$i] -join '')
                    }
                }
                Write-Output ([DateTime]::parse($CleanDateTaken))

            }
        }
    }
}

<#
    .Synopsis
       Robocopies all files in a folder that are taken after a given date. 
    .Description
       This function uses Get-DateTaken, meaning that for files without a date taken it will
       use the date created instead. The cutoff date can be specified either as a DateTime or
       by providing the file name of the oldest file to be copied. This file name should be 
       given as a relative path from the LiteralPath parameter. 
    .Parameter LiteralPath
       The directory from which to copy files. 
    .Parameter LiteralDestination
       The directory to which to copy files. 
    .Parameter FirstFile
       The earliest/oldest file within LiteralPath to be copied. Either this or CutOff should 
       be used, not both. 
    .Parameter CutOff
       Files with a date created more recently than/as recently as CutOff will be copied. 
       Either this or FirstFile should be used, not both.     
    .Parameter Recurse
       Switch parameter, if specified then the elligible files in LiteralPath's subdirectories
       will also be robocopied into LiteralDestination. Note that subdirectory structure is 
       not preserved.         
    .Example
       RoboCopy-AfterDate '.\dir1\' '.\dir2\' -CutOff "2023-12-01T07:34:42-5:00" -Recurse
       Robocopies all files in dir1 taken/created after 2023-12-01 12:34:42 to dir2. 
    .Outputs
       robocopy output.
    .Notes
       Intended for use with majority pictures, hence using my Get-DateTaken rather than 
       simply using date created. More specifically, this is intended for creating local 
       copies of images from iCloud for Windows' Photos folder on a local backup, using
       the date of the last local backup as the cutoff.  

       I know this violates best-practice naming, but I wanted it to be clear that robocopy
       is used. 
    .Functionality
       Uses robocopy to create copies of files more recent than a given date. 
    #>
function RoboCopy-AfterDate {
    param(
        [Parameter(Mandatory = $True)][string]$LiteralPath,
        [Parameter(Mandatory = $True)][string]$LiteralDestination,
        [Parameter(Mandatory = $True, ParameterSetName = 'file')][String]$FirstFile,
        [Parameter(Mandatory = $True, ParameterSetName = 'date')][datetime]$CutOff,
        [Switch]$Recurse
    )

    If ($PSCmdlet.ParameterSetName -eq 'file') {
        # Find date taken of cut off file 
        $CutOffFile = Get-Item (($LiteralPath, $FirstFile -join '\') -replace '\\\\', '\')
        $CutOff = Get-DateTaken $CutOffFile
    }

    # Get all files in source directory
    If ($Recurse) {
        $Files = Get-ChildItem $LiteralPath -Recurse -File
    }
    Else {
        $Files = Get-ChildItem $LiteralPath -File
    }

    # Copy all files more recent than/as recent as the cutoff 
    $Files | ForEach-Object {
        If ((Get-DateTaken $_.FullName) -ge ($CutOff)) {
            Write-Output (robocopy $($_.DirectoryName) "$LiteralDestination\" $_.Name /mt /r:100 /w:5)
        }
    }

}

<#
    .Synopsis
       Copies files, dynamically renaming them to avoid namespace collisions.
    .Description
       This function finds P - Q (where P and Q are two directories) and copies the files that 
       are elements of P - Q to a third directory, dynamically renaming files to prevent 
       namespace collisions that could occur if P has subdirectories or the destination folder 
       does not start empty. 
    .Parameter LiteralPPath
       The directory that (presumably) contains unique files. 
    .Parameter LiteralQPath
       The directory that contains some but (presumably) not all of the files in P. 
    .Parameter LiteralDestinationPath
       The directory that files found to be uniquely in P and not Q will be copied to. 
    .Parameter Recurse 
       Switch parameter, if specified then the sets P and Q will include all the files in 
       subdirectories of LiteralPPath and LiteralQPath. 
    .Parameter PassThru
       Switch parameter, if specified the paths of the copies are written to the pipeline (as 
       a System.IO.FileInfo).
    .Example
       Copy-UniqueFiles .\dir1\ .\dir2\ .\dir3\ 
       Copy all top-level files in dir1 but not dir2 to dir3, renaming the files as needed. 
    .Example
       Copy-UniqueFiles .\dir1\ .\dir2\ .\dir3\ -Recurse
       Copy all files in dir1 but not dir2 to dir3, renaming the files as needed. Note that 
       subdirectory structure is not preserved.  
    .Outputs
       [System.IO.FileInfo]
       If -PassThru is specified, the function returns the new files in the destination 
       folder.
    .Notes
       Name duplication is done by matching p.basename, so IMG-0001.png and IMG-0001.jpg 
       would be a name match. IMG-0001.jpg and IMG-00012.jpg would also be a match, as the 
       latter contains the former. 
   
       This has a time complexity of |P| * |Q| just to identify which files to copy, which is 
       clearly sub-optimal - I may fix it in future. One fix would be to use Get-Item instead 
       of filtering the contents of Q, but this was originally intended to find files that had 
       been mistakenly deleted from a backup folder built with Copy-WithRename, so files from 
       P might have been present in Q with _X appended to them, thus necessitating the pattern
       -matching approach. 
      .Functionality
       Copies files found to be uniquely in one directory but not another into a third, flat 
       directory, dynamically appending an integer counter to base names to avoid namespace 
       collisions. Logically, it finds the set difference P - Q. 
    #>
function Copy-UniqueFiles {
    param(
        [Parameter(Mandatory = $True)][Alias("PPath", "P")][String]$LiteralPPath,
        [Parameter(Mandatory = $True)][Alias("QPath", "Q")][String]$LiteralQPath,
        [Parameter(Mandatory = $True)][Alias("DestPath", "D")][String]$LiteralDestinationPath, 
        [Switch]$Recurse,
        [Switch]$PassThru

    )

    If ($Recurse) {
        $PFiles = Get-ChildItem $LiteralPPath -Recurse -File
        $QFiles = Get-ChildItem $LiteralQPath -Recurse -File
    }
    Else {
        $PFiles = Get-ChildItem $LiteralPPath -File
        $QFiles = Get-ChildItem $LiteralQPath -File
    }
  
    $Counter = 0

    foreach ($PFile in $PFiles) {
        # Report progress 
        $ProgressParameters = @{
            Activity        = "Finding and Copying Unique Files"
            Status          = "$(100 * $Counter / $PFiles.Length) Checked:"
            PercentComplete = 100 * $Counter / $PFiles.Length
        }
        Write-Progress @ProgressParameters 
        $Counter++ 

        # Create basename-based pattern to match 
        $PName = $PFile.BaseName
        $PNamePattern = "^$([Regex]::escape($PName))"

        # non-unique until proven unique 
        $InPNotQ = $False
        
        # Find files in Q which match the file in P's name 
        $NameMatches = @($QFiles | Where-Object { $_.Name -match $PNamePattern } )
        If ($NameMatches.Length -eq 0) {
            # unique name - can be considered unique (i.e. in P and not Q) 
            $InPNotQ = $True
        }
        Else {
            # non-unique name - check for unique date 
            $PDate = Get-DateTaken $PFile.FullName
            $DateMatches = @($NameMatches | Where-Object { (Get-DateTaken $_.FullName) -eq $PDate } )
            if ($DateMatches.Length -eq 0) {
                $InPNotQ = $True
            }
        }
 
        If ($InPNotQ) {
            # Copy the file
            Write-Verbose "$($PFile.Name) is an element of P - Q" 
            If ($PassThru) {
                Write-Output Copy-FileWithDynamicRename $PFile $LiteralDestinationPath -PassThru
            }
            Else {
                Copy-FileWithDynamicRename $PFile.FullName $LiteralDestinationPath 
            }
           
        }
    }
}

<#
    .Synopsis
       Sets the date created (and date taken of Exif files) to the earliest or latest of date 
       created, date modified and date taken. Date modified is not changed. 
    .Description
       This function changes the date attributes of a file to be either the earliest or latest
       of the date attributes. The earliest or latest date is considered the canonical date 
       for the file. 
    .Parameter Path
       The file to update. Wildcards are supported. 
    .Parameter UseLatest, 
       Switch parameter, if specified then the latest (i.e. most recent) date is used instead 
       of the earliest. 
    .Parameter IgnoreCreated 
       Switch parameter, if specified then only date taken and date modified are considered 
       sources: the date created will still be set to the canonical date.   
    .Parameter PassThru
       Switch parameter, if specified the modified objects are written to the pipeline (as 
       System.IO.FileInfo objects).
    .Example
       Set-CreationDate .\dir1\img1.JPG  -verbose -passthru
       Updates img1.JPG's date created and date taken to the earliest of date taken, date 
       created and date modified. 
    .Example
       Set-CreationDate .\dir1\img1.JPG -IgnoreCreated
       Updates img1.JPG's date created and date taken to the earliest of date taken and date 
       modified. 
    .Example
       Set-CreationDate .\dir1\text1.txt -UseLatest
       Updates text1.txt's date created to the latest of date created and date modified. 
    .Example
       Set-CreationDate .\dir1\text1.txt -IgnoreCreated
       Updates text1.txt's date created to date modified. 
    .Outputs
       [System.IO.FileInfo]
       If -PassThru is specified, the function returns the modified files.
    .Notes
       This was intended to deal with backup files that were created by copying original files
       and as such had incorrect date created information. It is quite heavy-handed and 
       assumes that the date taken and date modified attributes are still accurate, which may 
       not be true in your use case. 
    .Functionality
       Sets the date created (and date taken of Exif files) to the earliest or latest of date 
       created, date modified and date taken. Date modified is not changed. Date created can 
       be excluded from the reckoning, such that the canonical date is selected from date 
       taken and date modififed, but note that for non-Exif files this is equivalent to just 
       setting date created to equal date modified and can be done more simply. 
    #>
function Set-CreationDate {
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True)]
        [System.IO.FileInfo]
        $Path,

        [Alias('late')][Switch]$UseLatest, 
        [Alias('ic')][Switch]$IgnoreCreated, 
        [Switch]$PassThru
    )
    
    Begin {
        $ExifFormats = '.JPG', '.TIF', '.WAV', '.PNG', '.WEBP'
    }

    Process {
        # Start of code adapted from [ExifDateTime](https://github.com/chestercodes/ExifDateTime). Accessed 29/12/23. 
        # Cater for arrays of filenames and wild-cards by using Resolve-Path
        Write-Verbose -Message "Set-DateTaken processing input item '$Path'"
                        
        # Keep only the resolved paths that lead to files (not directories) 
        $FileItems = Resolve-Path -Path $Path -ErrorAction SilentlyContinue -ErrorVariable ResolveError | 
        ForEach-Object { Get-Item $_.Path } | 
        Where-Object { $_.PSIsContainer -eq $False }
        If ($ResolveError) {
            Write-Warning "Bad path '$Path' ($($ResolveError[0].CategoryInfo.Category))"
        } 

        # End of code adapted from ExifDateTime
        
        ForEach ($FileItem in $FileItems) {
            if ($EXIFFormats -contains $FileItem.Extension.ToUpper()) {
                Try {
                    $WithEXIF = Get-ExifDateTaken $FileItem.FullName
                    $DateTaken = $WithEXIF.ExifDateTaken
                }
                Catch {
                    $DateTaken = Get-DateTaken $FileItem.FullName
                }
            }
            Else {
                # Not an Exif file, so date taken is not expected 
                $DateTaken = $null
            }

            $DateCreated = $FileItem.CreationTime
            $DateModified = $FileItem.LastWriteTime

            $Canonical = $DateTaken
            If ($null -eq $DateTaken) {
                Write-Verbose "`tDateTaken: null"
            }
            Else {
                Write-Verbose "`tDateTaken: $($DateTaken.ToString('u'))"
            }
            Write-Verbose "`tDateCreated: $($DateCreated.ToString('u'))"
            Write-Verbose "`tDateModified: $($DateModified.ToString('u'))"

            If (!$Latest) {
                # Find earliest date associated with file 
                If ((!$IgnoreCreated) -and ($DateCreated -lt $Canonical -or $null -eq $Canonical)) {
                    $Canonical = $DateCreated
                    Write-Verbose "`tDateCreated was earlier: $($Canonical.ToString('u'))"
                }
                If ($DateModified -lt $Canonical -or $null -eq $Canonical) {
                    $Canonical = $DateModified
                    Write-Verbose "`tDateModified was earlier: $($Canonical.ToString('u'))"
                }
            }
            else {
                # Find latest date associated with file 
                if ((!$IgnoreCreated) -and ($DateCreated -gt $Canonical -or $null -eq $Canonical)) {
                    $Canonical = $DateCreated
                    Write-Verbose "`tDateCreated was later: $($Canonical.ToString('u'))"
                }
                if ($DateModified -gt $Canonical -or $null -eq $Canonical) {
                    $Canonical = $DateModified
                    Write-Verbose "`tDateModified was later: $($Canonical.ToString('u'))"
                }
            }

            # Set creation time to canonical time 
            $FileItem.CreationTime = $Canonical

            # Set date taken of Exif file to canonical time 
            if ($EXIFFormats -contains $FileItem.Extension.ToUpper()) {
                Update-ExifDateTaken -Path $FileItem.FullName -NewTime $Canonical
            }

            # Restore last write time (changed by Update-ExifDateTaken) 
            $FileItem.LastWriteTime = $DateModified

            If ($PassThru) {
                Write-Output $FileItem
            }
        }
    }
}

# Export everything 
Export-ModuleMember -Function * -Alias *