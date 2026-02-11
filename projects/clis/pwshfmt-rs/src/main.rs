use std::process;

fn main() {
    match pwshfmt_rs::run() {
        Ok(exit_code) => process::exit(exit_code),
        Err(error) => {
            eprintln!("{:?}", miette::Report::new(error));
            process::exit(1);
        }
    }
}
