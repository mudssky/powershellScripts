<#
.SYNOPSIS
    ZIP文件批量重命名为CBZ格式的脚本

.DESCRIPTION
    该脚本将当前目录下的所有ZIP文件重命名为CBZ格式。
    CBZ是漫画书压缩格式，本质上是包含图片文件的ZIP压缩包。

.EXAMPLE
    .\cbz.ps1
    将当前目录下的所有.zip文件重命名为.cbz文件

.NOTES
    CBZ格式常用于数字漫画书
    操作会直接重命名文件，请确保备份重要文件
    使用Windows命令行工具进行批量重命名
#>

cmd /c ren *.zip *.cbz