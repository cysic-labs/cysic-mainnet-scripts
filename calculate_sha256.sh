#!/bin/bash

# 遍历 github_release 目录下的所有文件
echo "library and program used for cysnet mainnet, version v1.0.0"
echo "|文件名 | sha256sum|"
echo "|- | -|"
find ./github_release -type f -print0 | while IFS= read -r -d '' file; do
    # 去除文件名中的 ./github_release/ 前缀
    cleaned_file=$(echo "$file" | sed 's/^\.\/github_release\///')
    # 计算文件的 sha256sum
    sha256=$(sha256sum "$file" | awk '{print $1}')
    # 格式化输出文件名和对应的 sha256sum
    printf "|%-60s | %s|\n" "$cleaned_file" "$sha256"
done