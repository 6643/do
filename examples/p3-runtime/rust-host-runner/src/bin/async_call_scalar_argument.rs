#[allow(dead_code)]
#[path = "async_call_component.rs"]
mod async_call_component;

fn main() -> anyhow::Result<()> {
    async_call_component::run_cli()
}
