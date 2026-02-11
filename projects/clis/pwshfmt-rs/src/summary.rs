use std::path::PathBuf;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RunMode {
    Check,
    Write,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileStatus {
    Unchanged,
    NeedsFix,
    Updated,
    Failed,
}

#[derive(Debug, Clone)]
pub struct FileReport {
    pub path: PathBuf,
    pub status: FileStatus,
    pub fallback_invoked: bool,
    pub fallback_changed: bool,
    pub command_fixes: usize,
    pub parameter_fixes: usize,
    pub detail: Option<String>,
}

impl FileReport {
    pub fn unchanged(path: PathBuf, command_fixes: usize, parameter_fixes: usize) -> Self {
        Self {
            path,
            status: FileStatus::Unchanged,
            fallback_invoked: false,
            fallback_changed: false,
            command_fixes,
            parameter_fixes,
            detail: None,
        }
    }

    pub fn needs_fix(path: PathBuf, command_fixes: usize, parameter_fixes: usize) -> Self {
        Self {
            path,
            status: FileStatus::NeedsFix,
            fallback_invoked: false,
            fallback_changed: false,
            command_fixes,
            parameter_fixes,
            detail: None,
        }
    }

    pub fn updated(path: PathBuf, command_fixes: usize, parameter_fixes: usize) -> Self {
        Self {
            path,
            status: FileStatus::Updated,
            fallback_invoked: false,
            fallback_changed: false,
            command_fixes,
            parameter_fixes,
            detail: None,
        }
    }

    pub fn failed(path: PathBuf, detail: impl Into<String>) -> Self {
        Self {
            path,
            status: FileStatus::Failed,
            fallback_invoked: false,
            fallback_changed: false,
            command_fixes: 0,
            parameter_fixes: 0,
            detail: Some(detail.into()),
        }
    }

    pub fn with_fallback(mut self, changed: bool) -> Self {
        self.fallback_invoked = true;
        self.fallback_changed = changed;
        self
    }
}

#[derive(Debug, Default, Clone)]
pub struct Summary {
    pub total: usize,
    pub unchanged: usize,
    pub needs_fix: usize,
    pub updated: usize,
    pub failed: usize,
    pub fallback_invoked: usize,
    pub fallback_changed: usize,
    pub command_fixes: usize,
    pub parameter_fixes: usize,
}

impl Summary {
    pub fn track(&mut self, report: &FileReport) {
        self.total += 1;
        self.command_fixes += report.command_fixes;
        self.parameter_fixes += report.parameter_fixes;

        match report.status {
            FileStatus::Unchanged => self.unchanged += 1,
            FileStatus::NeedsFix => self.needs_fix += 1,
            FileStatus::Updated => self.updated += 1,
            FileStatus::Failed => self.failed += 1,
        }

        if report.fallback_invoked {
            self.fallback_invoked += 1;
        }
        if report.fallback_changed {
            self.fallback_changed += 1;
        }
    }

    pub fn exit_code(&self, mode: RunMode) -> i32 {
        if self.failed > 0 {
            return 1;
        }

        if mode == RunMode::Check && self.needs_fix > 0 {
            return 2;
        }

        0
    }
}
