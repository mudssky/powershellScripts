<knowledge>
  <concept>
    - **Shebang**: 脚本开头的`#!/bin/bash`，指定解释器。
    - **变量**: 存储数据的命名空间，如`NAME="value"`。
    - **环境变量**: 影响shell会话和子进程的变量，如`PATH`, `HOME`。
    - **条件判断**: `if`, `elif`, `else`用于基于条件执行代码。
    - **循环**: `for`, `while`, `until`用于重复执行代码块。
    - **函数**: 封装可重用代码块，提高模块化。
    - **输入/输出重定向**: `>, >>, <, <<, 2>&1`用于改变命令的输入和输出。
    - **管道**: `|`用于将一个命令的输出作为另一个命令的输入。
    - **进程管理**: `ps`, `kill`, `nohup`, `&`用于管理后台进程。
    - **文件描述符**: 0(stdin), 1(stdout), 2(stderr)。
  </concept>
  <skill>
    - **基本命令**: `ls`, `cd`, `pwd`, `mkdir`, `rm`, `cp`, `mv`。
    - **文本处理**: `grep`, `awk`, `sed`, `cut`, `sort`, `uniq`。
    - **文件查找**: `find`, `locate`。
    - **系统信息**: `uname`, `df`, `du`, `free`, `top`。
    - **用户和权限**: `chmod`, `chown`, `sudo`, `su`。
    - **网络工具**: `curl`, `wget`, `ping`, `netstat`, `ss`。
    - **压缩/解压**: `tar`, `gzip`, `bzip2`, `zip`。
    - **正则表达式**: 在`grep`, `sed`, `awk`中使用。
    - **调试脚本**: 使用`set -x`, `echo`进行调试。
    - **参数处理**: `$1, $2, $@, $*`等。
  </skill>
  <tool>
    - **Bash**: 最常用的Shell解释器。
    - **Zsh**: 增强型Shell，兼容Bash。
    - **GNU Core Utilities**: 包含`grep`, `awk`, `sed`等。
    - **Vim/Nano**: 命令行文本编辑器。
    - **ShellCheck**: 静态分析工具，用于检查Shell脚本错误。
  </tool>
  <best-practice>
    - **脚本开头添加Shebang**。
    - **使用双引号引用变量**，避免单词分割和路径扩展问题。
    - **检查命令执行结果**，使用`$?`或`set -e`。
    - **使用函数组织代码**。
    - **提供清晰的注释**。
    - **避免使用`ls`解析文件名**。
    - **使用`local`声明函数内部变量**。
    - **处理特殊字符和空格**。
  </best-practice>
</knowledge>