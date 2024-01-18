#!/bin/sh
# 对git仓库的name和邮箱批量重命名,误切换造成个人信息泄露时可以抢救一下
git filter-branch --env-filter '

OLD_EMAIL="旧邮箱"
CORRECT_NAME="mudssky"
CORRECT_EMAIL="mudssky@gmail.com"

if [ "$GIT_COMMITTER_EMAIL" = "$OLD_EMAIL" ]
then
    export GIT_COMMITTER_NAME="$CORRECT_NAME"
    export GIT_COMMITTER_EMAIL="$CORRECT_EMAIL"
fi
if [ "$GIT_AUTHOR_EMAIL" = "$OLD_EMAIL" ]
then
    export GIT_AUTHOR_NAME="$CORRECT_NAME"
    export GIT_AUTHOR_EMAIL="$CORRECT_EMAIL"
fi
' --tag-name-filter cat -- --branches --tags
