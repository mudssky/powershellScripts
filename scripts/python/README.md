# Python Scripts

这里存放跨平台的 Python 自动化脚本。

## 依赖管理

本项目采用 **PEP 723** 标准管理依赖。
每个脚本头部都包含依赖声明，推荐使用 `uv` 运行。

## 脚本列表

### [model_generator.py](./model_generator.py)

自动从 Excel/CSV/TSV 文件生成 Pydantic 数据模型。

**用法:**

```bash
# 直接运行 (需安装 uv)
uv run scripts/python/model_generator.py data.xlsx

# 或者使用 bin 目录下的快捷命令 (需先运行 Manage-BinScripts.ps1)
model_generator data.xlsx
```

**参数:**
- `FILE_PATH`: 输入文件路径 (.xlsx, .csv, .tsv)
- `--name, -n`: 生成的类名 (默认: DataModel)
- `--sheet, -s`: Excel Sheet 名称或索引 (默认: 0)
- `--output, -o`: 输出文件路径 (默认: 打印到控制台)
