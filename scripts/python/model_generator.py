#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "pandas",
#     "openpyxl",
#     "pydantic",
#     "typer",
#     "rich",
# ]
# ///

"""
自动从 Excel/CSV/TSV 文件生成 Pydantic 数据模型。
支持自动类型推断、Optional 字段检测和别名处理。
"""

from typing import Any

import pandas as pd
import typer
from rich.console import Console
from rich.syntax import Syntax

app = typer.Typer(help="Generate Pydantic models from data files (xlsx, csv, tsv).")
console = Console()


def get_python_type(dtype: str, sample_val: Any = None) -> str:
    """Map pandas dtype to python type string."""
    dtype_str = str(dtype)
    if "int" in dtype_str:
        return "int"
    elif "float" in dtype_str:
        return "float"
    elif "bool" in dtype_str:
        return "bool"
    elif "datetime" in dtype_str:
        return "datetime"
    elif "object" in dtype_str:
        # Check if it's strictly string or mixed
        if isinstance(sample_val, str):
            return "str"
        return "str"  # Default to str for object types usually
    return "Any"


def sanitize_field_name(name: str, index: int) -> str:
    """Sanitize column name to be a valid python identifier."""
    clean_name = str(name).strip().replace(" ", "_").replace("-", "_").replace(".", "_")

    # Handle empty or invalid names
    if not clean_name:
        return f"col_{index}"

    # Check if valid identifier and not starting with digit
    if clean_name.isidentifier() and not clean_name[0].isdigit():
        return clean_name

    return f"col_{index}_{clean_name}" if clean_name else f"col_{index}"


@app.command()
def generate(
    file_path: str = typer.Argument(..., help="Path to the data file (.xlsx, .csv, .tsv)"),
    class_name: str = typer.Option("DataModel", "--name", "-n", help="Name of the generated Pydantic class"),
    sheet_name: str = typer.Option(0, "--sheet", "-s", help="Sheet name or index for Excel files"),
    output_file: str | None = typer.Option(None, "--output", "-o", help="Output file path (default: stdout)"),
):
    """
    Analyze a data file and generate a Pydantic model.
    """
    try:
        # Load data based on extension
        if file_path.endswith((".xlsx", ".xls")):
            df = pd.read_excel(file_path, sheet_name=sheet_name)
        elif file_path.endswith(".csv"):
            df = pd.read_csv(file_path)
        elif file_path.endswith(".tsv"):
            df = pd.read_csv(file_path, sep="\t")
        else:
            console.print(f"[red]Error:[/red] Unsupported file format for '{file_path}'")
            raise typer.Exit(code=1)

    except Exception as e:
        console.print(f"[red]Error reading file:[/red] {e}")
        raise typer.Exit(code=1) from None

    lines = []
    lines.append("from pydantic import BaseModel, Field")
    lines.append("from typing import Optional, Any")
    lines.append("from datetime import datetime")
    lines.append("")
    lines.append(f"class {class_name}(BaseModel):")

    if df.empty:
        lines.append("    pass")
    else:
        for idx, column in enumerate(df.columns):
            series = df[column]
            dtype = series.dtype
            is_nullable = series.isnull().any()

            # Get sample non-null value for better type inference
            valid_samples = series.dropna()
            sample_val = valid_samples.iloc[0] if not valid_samples.empty else None

            python_type = get_python_type(dtype, sample_val)

            # Sanitize field name
            field_name = sanitize_field_name(column, idx)

            # Construct field definition
            type_hint = f"Optional[{python_type}]" if is_nullable else python_type
            default_val = " = None" if is_nullable else ""

            field_def = f"    {field_name}: {type_hint}"

            # Add Field(alias=...) if name changed
            if field_name != column:
                if default_val:
                    field_def += f" = Field(alias='{column}', default=None)"
                else:
                    field_def += f" = Field(alias='{column}')"
            else:
                field_def += default_val

            lines.append(field_def)

    code = "\n".join(lines)

    if output_file:
        try:
            with open(output_file, "w", encoding="utf-8") as f:
                f.write(code)
            console.print(f"[green]Successfully wrote model to {output_file}[/green]")
        except Exception as e:
            console.print(f"[red]Error writing output:[/red] {e}")
            raise typer.Exit(code=1) from None
    else:
        syntax = Syntax(code, "python", theme="monokai", line_numbers=True)
        console.print(syntax)


if __name__ == "__main__":
    app()
