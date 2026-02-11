mod common;

use clap::{Parser, error::ErrorKind};
use pwshfmt_rs::{
    cli::Cli,
    config::{self, Config},
};

#[test]
fn cli_supports_help_output() {
    let error = Cli::try_parse_from(["pwshfmt-rs", "--help"]).expect_err("help should short-circuit");
    assert_eq!(error.kind(), ErrorKind::DisplayHelp);
}

#[test]
fn cli_requires_subcommand() {
    let error = Cli::try_parse_from(["pwshfmt-rs"]).expect_err("subcommand should be required");
    assert_eq!(error.kind(), ErrorKind::DisplayHelpOnMissingArgumentOrSubcommand);
}

#[test]
fn config_uses_defaults_when_file_missing() {
    let workspace = common::create_workspace();
    let fallback = common::write_file(workspace.path(), "fallback.ps1", "# fallback");

    let cli = Cli::try_parse_from([
        "pwshfmt-rs",
        "check",
        "--path",
        "scripts/demo.ps1",
        "--fallback-script",
        fallback
            .strip_prefix(workspace.path())
            .expect("relative fallback")
            .to_string_lossy()
            .as_ref(),
    ])
    .expect("parse cli");

    let config = config::load(&cli, workspace.path()).expect("load config");

    assert_eq!(config, Config {
        git_changed: false,
        paths: vec!["scripts/demo.ps1".to_string()],
        recurse: false,
        strict_fallback: false,
        fallback_script: std::path::PathBuf::from("fallback.ps1"),
    });
}

#[test]
fn config_layering_is_cli_over_env_over_file_over_defaults() {
    let workspace = common::create_workspace();
    let fallback = common::write_file(workspace.path(), "fallback.ps1", "# fallback");

    common::write_file(
        workspace.path(),
        "pwshfmt-rs.toml",
        r#"
git_changed = true
paths = ["from-config.ps1"]
recurse = false
strict_fallback = false
fallback_script = "from-config-fallback.ps1"
"#,
    );

    let cli = Cli::try_parse_from([
        "pwshfmt-rs",
        "write",
        "--path",
        "from-cli.ps1",
        "--strict-fallback",
        "--fallback-script",
        fallback
            .strip_prefix(workspace.path())
            .expect("relative fallback")
            .to_string_lossy()
            .as_ref(),
    ])
    .expect("parse cli");

    temp_env::with_var("PWSHFMT_RS_RECURSE", Some("true"), || {
        let config = config::load(&cli, workspace.path()).expect("load layered config");

        assert!(config.git_changed);
        assert_eq!(config.paths, vec!["from-cli.ps1".to_string()]);
        assert!(config.recurse);
        assert!(config.strict_fallback);
        assert_eq!(config.fallback_script, std::path::PathBuf::from("fallback.ps1"));
    });
}
