# 需要先安装
# pip install git-filter-repo 

git filter-repo --commit-callback '
# 定义变量
OLD_EMAIL = b"oldemail@example.com"
NEW_NAME = b"mudssky"
NEW_EMAIL = b"mudssky@gmail.com"

# 修改作者信息
if commit.author_email == OLD_EMAIL:
    commit.author_name = NEW_NAME
    commit.author_email = NEW_EMAIL

# 修改提交者信息
if commit.committer_email == OLD_EMAIL:
    commit.committer_name = NEW_NAME
    commit.committer_email = NEW_EMAIL
'
