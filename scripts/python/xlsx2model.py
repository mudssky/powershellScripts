#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "pandas",
#     "openpyxl",
#     "datamodel-code-generator",
# ]
# ///

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import pandas as pd


def main():
    parser = argparse.ArgumentParser(description="Generate Pydantic models from Excel/CSV/TSV files.")
    parser.add_argument("input_file", help="Path to the input file (.xlsx, .xls, .csv, .tsv)")
    parser.add_argument("--output", "-o", help="Path to the output file (default: stdout)")
    parser.add_argument(
        "--class-name",
        "-c",
        default="Model",
        help="Name of the generated class (default: Model)",
    )
    parser.add_argument("--sheet", "-s", help="Sheet name (for Excel files), defaults to first sheet")

    args = parser.parse_args()

    input_path = Path(args.input_file)
    if not input_path.exists():
        print(f"Error: File not found: {input_path}", file=sys.stderr)
        sys.exit(1)

    # Determine file type and read content
    suffix = input_path.suffix.lower()
    csv_content = ""

    try:
        if suffix in [".xlsx", ".xls"]:
            # Read Excel
            df = pd.read_excel(input_path, sheet_name=args.sheet if args.sheet else 0)
            # Convert to CSV string
            csv_content = df.to_csv(index=False)
        elif suffix == ".csv":
            with open(input_path, encoding="utf-8") as f:
                csv_content = f.read()
        elif suffix == ".tsv":
            df = pd.read_csv(input_path, sep="\t")
            csv_content = df.to_csv(index=False)
        else:
            print(f"Error: Unsupported file extension: {suffix}", file=sys.stderr)
            sys.exit(1)

    except Exception as e:
        print(f"Error reading file: {e}", file=sys.stderr)
        sys.exit(1)

    # Use subprocess to call datamodel-codegen
    # Create a temporary file for the CSV content
    with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False, encoding="utf-8") as tmp_csv:
        tmp_csv.write(csv_content)
        tmp_csv_path = tmp_csv.name

    try:
        # Construct command
        # We use sys.executable -m datamodel_code_generator to avoid PATH issues if possible,
        # but datamodel-codegen is a CLI entry point.
        # In 'uv run', the scripts are in the path.
        cmd = [
            "datamodel-codegen",
            "--input",
            tmp_csv_path,
            "--input-file-type",
            "csv",
            "--class-name",
            args.class_name,
            "--output-model-type",
            "pydantic_v2.BaseModel",
            "--snake-case-field",
            "--use-default",
            "--use-schema-description",
            "--use-field-description",
        ]

        if args.output:
            cmd.extend(["--output", args.output])

        # Run command
        # shell=True on Windows might be needed if datamodel-codegen is a batch file wrapper?
        # But uv usually handles this. Let's try without shell=True first.
        # On Windows, python scripts installed by pip are usually .exe wrappers or scripts in Scripts dir.
        result = subprocess.run(cmd, capture_output=True, text=True, shell=os.name == "nt")

        if result.returncode != 0:
            print(f"Error running datamodel-codegen: {result.stderr}", file=sys.stderr)
            # If command not found, try with python -m
            if "not found" in result.stderr or result.returncode == 127 or (os.name == "nt" and result.returncode == 1):
                print(
                    "Retrying with python -m datamodel_code_generator...",
                    file=sys.stderr,
                )
                cmd[0] = sys.executable
                cmd.insert(1, "-m")
                cmd.insert(2, "datamodel_code_generator")
                result = subprocess.run(cmd, capture_output=True, text=True)
                if result.returncode != 0:
                    print(f"Final error: {result.stderr}", file=sys.stderr)
                    sys.exit(1)

        if not args.output:
            print(result.stdout)
        else:
            print(f"Model generated at: {args.output}")

    except FileNotFoundError:
        print(
            "Error: datamodel-codegen executable not found. Ensure it is installed in the dependencies.",
            file=sys.stderr,
        )
        sys.exit(1)
    except Exception as e:
        print(f"Unexpected error: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        if os.path.exists(tmp_csv_path):
            os.unlink(tmp_csv_path)


if __name__ == "__main__":
    main()
