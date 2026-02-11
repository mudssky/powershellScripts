#[derive(Debug, Clone)]
pub struct FormatOutcome {
    pub formatted: String,
    pub command_fixes: usize,
    pub parameter_fixes: usize,
    pub unsafe_detected: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ScanState {
    Code,
    SingleQuoted,
    DoubleQuoted,
    LineComment,
    BlockComment,
    HereSingleQuoted,
    HereDoubleQuoted,
}

pub fn format_content(input: &str) -> FormatOutcome {
    let mut output = String::with_capacity(input.len());
    let mut state = ScanState::Code;
    let mut index = 0usize;

    let mut command_fixes = 0usize;
    let mut parameter_fixes = 0usize;
    let mut unsafe_detected = false;

    while index < input.len() {
        match state {
            ScanState::Code => {
                if starts_with_at(input, index, "<#") {
                    output.push_str("<#");
                    index += 2;
                    state = ScanState::BlockComment;
                    continue;
                }

                if starts_with_at(input, index, "@\"") {
                    output.push_str("@\"");
                    index += 2;
                    state = ScanState::HereDoubleQuoted;
                    continue;
                }

                if starts_with_at(input, index, "@'") {
                    output.push_str("@'");
                    index += 2;
                    state = ScanState::HereSingleQuoted;
                    continue;
                }

                let Some(character) = input[index..].chars().next() else {
                    break;
                };
                let char_len = character.len_utf8();

                if character == '#' {
                    output.push('#');
                    index += char_len;
                    state = ScanState::LineComment;
                    continue;
                }

                if character == '\'' {
                    output.push('\'');
                    index += char_len;
                    state = ScanState::SingleQuoted;
                    continue;
                }

                if character == '"' {
                    output.push('"');
                    index += char_len;
                    state = ScanState::DoubleQuoted;
                    continue;
                }

                if character == '&' && is_dynamic_call_operator(input, index) {
                    unsafe_detected = true;
                    output.push('&');
                    index += char_len;
                    continue;
                }

                if character == '-' {
                    if let Some((token, next_index)) = read_word(input, index + char_len) {
                        if let Some(canonical) = canonical_parameter(token) {
                            if token != canonical {
                                parameter_fixes += 1;
                            }
                            output.push('-');
                            output.push_str(canonical);
                            index = next_index;
                            continue;
                        }
                    }
                }

                if character.is_ascii_alphabetic() {
                    if let Some((token, next_index)) = read_command_token(input, index) {
                        let token_lower = token.to_ascii_lowercase();
                        if token_lower == "invoke-expression" {
                            unsafe_detected = true;
                        }

                        if let Some(canonical) = canonical_command(&token_lower) {
                            if token != canonical {
                                command_fixes += 1;
                            }
                            output.push_str(canonical);
                        } else {
                            output.push_str(token);
                        }

                        index = next_index;
                        continue;
                    }
                }

                output.push(character);
                index += char_len;
            }
            ScanState::SingleQuoted => {
                let Some(character) = input[index..].chars().next() else {
                    break;
                };
                let char_len = character.len_utf8();

                output.push(character);
                index += char_len;

                if character == '\'' {
                    if starts_with_at(input, index, "'") {
                        output.push('\'');
                        index += 1;
                    } else {
                        state = ScanState::Code;
                    }
                }
            }
            ScanState::DoubleQuoted => {
                let Some(character) = input[index..].chars().next() else {
                    break;
                };
                let char_len = character.len_utf8();

                output.push(character);
                index += char_len;

                if character == '`' {
                    if let Some(escaped) = input[index..].chars().next() {
                        output.push(escaped);
                        index += escaped.len_utf8();
                    }
                    continue;
                }

                if character == '"' {
                    state = ScanState::Code;
                }
            }
            ScanState::LineComment => {
                let Some(character) = input[index..].chars().next() else {
                    break;
                };
                let char_len = character.len_utf8();
                output.push(character);
                index += char_len;

                if character == '\n' {
                    state = ScanState::Code;
                }
            }
            ScanState::BlockComment => {
                if starts_with_at(input, index, "#>") {
                    output.push_str("#>");
                    index += 2;
                    state = ScanState::Code;
                    continue;
                }

                let Some(character) = input[index..].chars().next() else {
                    break;
                };
                output.push(character);
                index += character.len_utf8();
            }
            ScanState::HereSingleQuoted => {
                if starts_with_at(input, index, "'@") && is_line_start(input, index) {
                    output.push_str("'@");
                    index += 2;
                    state = ScanState::Code;
                    continue;
                }

                let Some(character) = input[index..].chars().next() else {
                    break;
                };
                output.push(character);
                index += character.len_utf8();
            }
            ScanState::HereDoubleQuoted => {
                if starts_with_at(input, index, "\"@") && is_line_start(input, index) {
                    output.push_str("\"@");
                    index += 2;
                    state = ScanState::Code;
                    continue;
                }

                let Some(character) = input[index..].chars().next() else {
                    break;
                };
                output.push(character);
                index += character.len_utf8();
            }
        }
    }

    FormatOutcome {
        formatted: output,
        command_fixes,
        parameter_fixes,
        unsafe_detected,
    }
}

fn starts_with_at(input: &str, index: usize, pattern: &str) -> bool {
    input.get(index..).is_some_and(|value| value.starts_with(pattern))
}

fn read_word(input: &str, start: usize) -> Option<(&str, usize)> {
    if start >= input.len() {
        return None;
    }

    let mut end = start;
    let mut has_character = false;
    for (offset, character) in input[start..].char_indices() {
        if character.is_ascii_alphanumeric() {
            has_character = true;
            end = start + offset + character.len_utf8();
            continue;
        }
        break;
    }

    if !has_character {
        return None;
    }

    Some((&input[start..end], end))
}

fn read_command_token(input: &str, start: usize) -> Option<(&str, usize)> {
    if start >= input.len() {
        return None;
    }

    let mut end = start;
    for (offset, character) in input[start..].char_indices() {
        if character.is_ascii_alphanumeric() || character == '-' {
            end = start + offset + character.len_utf8();
            continue;
        }
        break;
    }

    if end == start {
        return None;
    }

    Some((&input[start..end], end))
}

fn is_line_start(input: &str, index: usize) -> bool {
    if index == 0 {
        return true;
    }

    input[..index]
        .chars()
        .next_back()
        .is_some_and(|value| value == '\n')
}

fn is_dynamic_call_operator(input: &str, index: usize) -> bool {
    let mut cursor = index + '&'.len_utf8();

    while let Some(character) = input.get(cursor..).and_then(|value| value.chars().next()) {
        if character.is_whitespace() {
            cursor += character.len_utf8();
            continue;
        }

        return matches!(character, '$' | '(' | '{' | '\'' | '"');
    }

    false
}

fn canonical_command(token_lower: &str) -> Option<&'static str> {
    match token_lower {
        "add-content" => Some("Add-Content"),
        "compare-object" => Some("Compare-Object"),
        "convertfrom-json" => Some("ConvertFrom-Json"),
        "convertto-json" => Some("ConvertTo-Json"),
        "export-csv" => Some("Export-Csv"),
        "foreach-object" => Some("ForEach-Object"),
        "get-childitem" => Some("Get-ChildItem"),
        "get-command" => Some("Get-Command"),
        "get-content" => Some("Get-Content"),
        "get-date" => Some("Get-Date"),
        "get-item" => Some("Get-Item"),
        "get-location" => Some("Get-Location"),
        "get-process" => Some("Get-Process"),
        "import-csv" => Some("Import-Csv"),
        "import-module" => Some("Import-Module"),
        "install-module" => Some("Install-Module"),
        "invoke-command" => Some("Invoke-Command"),
        "invoke-expression" => Some("Invoke-Expression"),
        "invoke-formatter" => Some("Invoke-Formatter"),
        "join-path" => Some("Join-Path"),
        "measure-object" => Some("Measure-Object"),
        "new-item" => Some("New-Item"),
        "out-file" => Some("Out-File"),
        "remove-item" => Some("Remove-Item"),
        "resolve-path" => Some("Resolve-Path"),
        "select-object" => Some("Select-Object"),
        "set-content" => Some("Set-Content"),
        "set-item" => Some("Set-Item"),
        "set-location" => Some("Set-Location"),
        "set-strictmode" => Some("Set-StrictMode"),
        "sort-object" => Some("Sort-Object"),
        "split-path" => Some("Split-Path"),
        "start-process" => Some("Start-Process"),
        "stop-process" => Some("Stop-Process"),
        "test-path" => Some("Test-Path"),
        "where-object" => Some("Where-Object"),
        "write-debug" => Some("Write-Debug"),
        "write-error" => Some("Write-Error"),
        "write-host" => Some("Write-Host"),
        "write-output" => Some("Write-Output"),
        "write-verbose" => Some("Write-Verbose"),
        "write-warning" => Some("Write-Warning"),
        _ => None,
    }
}

fn canonical_parameter(token: &str) -> Option<&'static str> {
    match token.to_ascii_lowercase().as_str() {
        "all" => Some("All"),
        "argumentlist" => Some("ArgumentList"),
        "as" => Some("As"),
        "command" => Some("Command"),
        "confirm" => Some("Confirm"),
        "depth" => Some("Depth"),
        "debug" => Some("Debug"),
        "erroraction" => Some("ErrorAction"),
        "exclude" => Some("Exclude"),
        "file" => Some("File"),
        "filter" => Some("Filter"),
        "force" => Some("Force"),
        "gitchanged" => Some("GitChanged"),
        "help" => Some("Help"),
        "include" => Some("Include"),
        "inputobject" => Some("InputObject"),
        "literalpath" => Some("LiteralPath"),
        "modulename" => Some("ModuleName"),
        "name" => Some("Name"),
        "noprofile" => Some("NoProfile"),
        "outputpath" => Some("OutputPath"),
        "path" => Some("Path"),
        "pipelinevariable" => Some("PipelineVariable"),
        "recurse" => Some("Recurse"),
        "scope" => Some("Scope"),
        "scriptblock" => Some("ScriptBlock"),
        "settings" => Some("Settings"),
        "showonly" => Some("ShowOnly"),
        "strict" => Some("Strict"),
        "value" => Some("Value"),
        "verbose" => Some("Verbose"),
        "warningaction" => Some("WarningAction"),
        "whatif" => Some("WhatIf"),
        "write" => Some("Write"),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::format_content;

    #[test]
    fn fixes_command_and_parameter_casing() {
        let input = "get-childitem -path .\n";
        let output = format_content(input);

        assert_eq!(output.formatted, "Get-ChildItem -Path .\n");
        assert_eq!(output.command_fixes, 1);
        assert_eq!(output.parameter_fixes, 1);
        assert!(!output.unsafe_detected);
    }

    #[test]
    fn keeps_comments_and_strings_unchanged() {
        let input = "Write-Host \"get-childitem -path\" # get-childitem -path\n";
        let output = format_content(input);

        assert_eq!(output.formatted, input);
        assert_eq!(output.command_fixes, 0);
        assert_eq!(output.parameter_fixes, 0);
    }

    #[test]
    fn detects_dynamic_call_operator_as_unsafe() {
        let input = "& $scriptBlock\n";
        let output = format_content(input);

        assert!(output.unsafe_detected);
    }

    #[test]
    fn keeps_here_string_body_unchanged() {
        let input = "@\"\nget-childitem -path .\n\"@\n";
        let output = format_content(input);

        assert_eq!(output.formatted, input);
    }
}
