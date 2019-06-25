# VideotoAAC   Mp4封装 即 h264视频流 + aac 音频流，抽取aac相当于直接拷贝视频中的音频流就没有转码的损失
param(
    [switch]$pause
)
$count=0;
$videos = Get-ChildItem -File -Recurse  *.mp4,*.flv,*.ts  

$videos.foreach{ 
            $audioFilePath=($_.FullName.Substring(0,$_.FullName.Length-$_.Extension.Length)+'.m4a')
            ffmpeg -i $_.FullName -acodec copy -vn  $audioFilePath
            ;$count+=1;
            if($pause){
                Write-Host -ForegroundColor Yellow "输入e移动当前文件到error文件夹，并且删除已经准换好的音频文件，输入其他字母不进行任何操作"
                $input=Read-Host
                if($input -eq 'e' ){
                    if( -not (Test-Path 'error')  ){
                     New-Item -ItemType Directory   -Name 'error'  
                    }
                    
                    Move-Item $_   './error/'
                    Write-Host -ForegroundColor Green "移动 $($_.Name)到 error目录"
                    Remove-Item  -Path $audioFilePath
                    Write-Host -ForegroundColor Yellow "删除 $($audioFilePath)"
                }
            }
            };
            
            
            
Write-Host -ForegroundColor Green "mp4 counts: $count"
