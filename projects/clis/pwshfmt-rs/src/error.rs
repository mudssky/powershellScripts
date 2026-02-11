use std::io;
use std::path::PathBuf;

use miette::Diagnostic;
use thiserror::Error;

pub type Result<T> = std::result::Result<T, AppError>;

#[derive(Debug, Error, Diagnostic)]
pub enum AppError {
    #[error("{message}")]
    #[diagnostic(code(pwshfmt::invalid_arguments))]
    InvalidArguments { message: String },

    #[error("配置加载失败")]
    #[diagnostic(code(pwshfmt::config::load))]
    ConfigLoad {
        #[source]
        source: Box<figment::Error>,
    },

    #[error("显式指定的配置文件不存在: {path}")]
    #[diagnostic(code(pwshfmt::config::not_found))]
    ConfigFileMissing { path: PathBuf },

    #[error("I/O 操作失败: {operation}: {path}")]
    #[diagnostic(code(pwshfmt::io::failed))]
    Io {
        operation: &'static str,
        path: PathBuf,
        #[source]
        source: io::Error,
    },

    #[error("Glob 模式无效: {pattern}")]
    #[diagnostic(code(pwshfmt::discovery::glob_invalid))]
    InvalidGlob {
        pattern: String,
        #[source]
        source: globset::Error,
    },

    #[error("Git 命令执行失败: {message}")]
    #[diagnostic(code(pwshfmt::discovery::git_failed))]
    GitCommandFailed { message: String },

    #[error("严格回退失败: {path} ({message})")]
    #[diagnostic(code(pwshfmt::fallback::failed))]
    FallbackFailed { path: PathBuf, message: String },
}

impl AppError {
    pub fn invalid_arguments(message: impl Into<String>) -> Self {
        Self::InvalidArguments {
            message: message.into(),
        }
    }

    pub fn io(operation: &'static str, path: impl Into<PathBuf>, source: io::Error) -> Self {
        Self::Io {
            operation,
            path: path.into(),
            source,
        }
    }
}
