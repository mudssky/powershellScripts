<#
.SYNOPSIS
  Outputs to a UTF-8-encoded file *without a BOM* (byte-order mark).
 
.DESCRIPTION
  Mimics the most important aspects of Out-File:
  * Input objects are sent to Out-String first.
  * -Append allows you to append to an existing file, -NoClobber prevents
    overwriting of an existing file.
    -Append dones't seem to work. 周蒙牛(zhoujin7) comments.
  * -Width allows you to specify the line width for the text representations
     of input objects that aren't strings.
  However, it is not a complete implementation of all Out-String parameters:
  * Only a literal output path is supported, and only as a parameter.
  * -Force is supported. It write by 周蒙牛(zhoujin7).
    Indicates that the cmdlet overwrites an existing read-only file.
  * -NewLineType allows you to specify the type of newline. It write by 周蒙牛(zhoujin7).
    The optional types are 'windows','unix','mac'.
    Default type is 'unix'.
   
  Caveat: *All* pipeline input is buffered before writing output starts,
          but the string representations are generated and written to the target
          file one by one.
 
.NOTES
  The raison d'être for this advanced function is that, as of PowerShell v5,
  Out-File still lacks the ability to write UTF-8 files without a BOM:
  using -Encoding UTF8 invariably prepends a BOM.
 
  Copyright (c) 2017 Michael Klement  (http://same2u.net),
  released under the [MIT license](https://spdx.org/licenses/MIT#licenseText).
 
#>
function Out-FileUtf8NoBom
{
     
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$LiteralPath,
        [switch]$Append,
        [switch]$NoClobber,
        [AllowNull()]
        [int]$Width,
        [Parameter(ValueFromPipeline)]
        $InputObject,
        [switch]$Force,
        [ValidateSet('windows', 'unix', 'mac')]
        [String]$NewLineType = 'unix'
    )
     
    #requires -version 3
     
    # Make sure that the .NET framework sees the same working dir. as PS
    # and resolve the input path to a full path.
    [System.IO.Directory]::SetCurrentDirectory($PWD) # Caveat: .NET Core doesn't support [Environment]::CurrentDirectory
    $LiteralPath = [IO.Path]::GetFullPath($LiteralPath)
     
    #It write by 周蒙牛(zhoujin7)
    if (Test-Path -LiteralPath $LiteralPath)
    {
        $file = Get-Item -LiteralPath $LiteralPath -Force
         
        if (!($file.IsReadOnly))
        {
            Remove-Item -LiteralPath $LiteralPath -Force
        }
        else
        {
            Throw [IO.IOException] "The file '$LiteralPath' is read-only!"
        }
    }
     
    #It write by 周蒙牛(zhoujin7)
    if ($Force -and (Test-Path -LiteralPath $LiteralPath))
    {
        Remove-Item -LiteralPath $LiteralPath -Force
    }
     
    # If -NoClobber was specified, throw an exception if the target file already
    # exists.
    if ($NoClobber -and (Test-Path $LiteralPath))
    {
        Throw [IO.IOException] "The file '$LiteralPath' already exists."
    }
     
    # Create a StreamWriter object.
    # Note that we take advantage of the fact that the StreamWriter class by default:
    # - uses UTF-8 encoding
    # - without a BOM.
    $sw = New-Object IO.StreamWriter $LiteralPath, $Append
     
    $htOutStringArgs = @{ }
    if ($Width)
    {
        $htOutStringArgs += @{ Width = $Width }
    }
     
    # Note: By not using begin / process / end blocks, we're effectively running
    #       in the end block, which means that all pipeline input has already
    #       been collected in automatic variable $Input.
    #       We must use this approach, because using | Out-String individually
    #       in each iteration of a process block would format each input object
    #       with an indvidual header.
    try
    {
        #It write by 周蒙牛(zhoujin7)
        switch ($NewLineType)
        {
            'windows' {
                $NewLine = "`r`n"
                break
            }
            'unix' {
                $NewLine = "`n"
                break
            }
            'mac' {
                $NewLine = "`r"
                break
            }
        }
 
        $Input | Out-String -Stream @htOutStringArgs | ForEach-Object { $sw.Write("$_$NewLine") }
    }
    finally
    {
        $sw.Dispose()
    }
     
}
