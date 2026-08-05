use anyhow::{Context, Result, bail};
use std::collections::VecDeque;
use std::future::Future;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{
    Component, Destination, FutureReader, Linker, Resource, ResourceTable, ResourceType,
    StreamProducer, StreamReader, StreamResult, VecBuffer,
};
use wasmtime::{Config, Engine, Store, StoreContextMut};

const SOURCE_INSTANCE: &str = "do:record-resource-stream-probe/source@0.1.0";
const PROBE_INSTANCE: &str = "do:record-resource-stream-probe/probe@0.1.0";
const SOURCE_MULTI_INSTANCE: &str = "do:record-resource-stream-multi/source@0.1.0";
const PROBE_MULTI_INSTANCE: &str = "do:record-resource-stream-multi/probe@0.1.0";
const SOURCE_NESTED_INSTANCE: &str = "do:record-resource-stream-nested/source@0.1.0";
const PROBE_NESTED_INSTANCE: &str = "do:record-resource-stream-nested/probe@0.1.0";
const SOURCE_NESTED_TWO_INSTANCE: &str = "do:record-resource-stream-nested-two-level/source@0.1.0";
const PROBE_NESTED_TWO_INSTANCE: &str = "do:record-resource-stream-nested-two-level/probe@0.1.0";
const SOURCE_NESTED_THREE_INSTANCE: &str =
    "do:record-resource-stream-nested-three-level/source@0.1.0";
const PROBE_NESTED_THREE_INSTANCE: &str =
    "do:record-resource-stream-nested-three-level/probe@0.1.0";
const SOURCE_NESTED_FOUR_INSTANCE: &str =
    "do:record-resource-stream-nested-four-level/source@0.1.0";
const PROBE_NESTED_FOUR_INSTANCE: &str = "do:record-resource-stream-nested-four-level/probe@0.1.0";
const SOURCE_NESTED_FIVE_INSTANCE: &str =
    "do:record-resource-stream-nested-five-level/source@0.1.0";
const PROBE_NESTED_FIVE_INSTANCE: &str = "do:record-resource-stream-nested-five-level/probe@0.1.0";
const SOURCE_NESTED_SIX_INSTANCE: &str = "do:record-resource-stream-nested-six-level/source@0.1.0";
const PROBE_NESTED_SIX_INSTANCE: &str = "do:record-resource-stream-nested-six-level/probe@0.1.0";
const SOURCE_MULTIPLE_NESTED_INSTANCE: &str =
    "do:record-resource-stream-multiple-nested/source@0.1.0";
const PROBE_MULTIPLE_NESTED_INSTANCE: &str =
    "do:record-resource-stream-multiple-nested/probe@0.1.0";

pub struct Ticket {
    _value: u32,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct ResourceEntry {
    id: u32,
    ticket: Resource<Ticket>,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct ResourceEntryMulti {
    id: u32,
    left: Resource<Ticket>,
    right: Resource<Ticket>,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct InnerEntry {
    ticket: Resource<Ticket>,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct ResourceEntryNested {
    inner: InnerEntry,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct DeepEntry {
    ticket: Resource<Ticket>,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct InnerEntryNestedTwo {
    deep: DeepEntry,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct ResourceEntryNestedTwo {
    inner: InnerEntryNestedTwo,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct DeeperEntryNestedThree {
    ticket: Resource<Ticket>,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct DeepEntryNestedThree {
    deeper: DeeperEntryNestedThree,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct InnerEntryNestedThree {
    deep: DeepEntryNestedThree,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct ResourceEntryNestedThree {
    inner: InnerEntryNestedThree,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct DeepestEntryNestedFour {
    ticket: Resource<Ticket>,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct DeeperEntryNestedFour {
    deepest: DeepestEntryNestedFour,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct DeepEntryNestedFour {
    deeper: DeeperEntryNestedFour,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct InnerEntryNestedFour {
    deep: DeepEntryNestedFour,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct ResourceEntryNestedFour {
    inner: InnerEntryNestedFour,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct UltraEntryNestedFive {
    ticket: Resource<Ticket>,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct DeepestEntryNestedFive {
    ultra: UltraEntryNestedFive,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct DeeperEntryNestedFive {
    deepest: DeepestEntryNestedFive,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct DeepEntryNestedFive {
    deeper: DeeperEntryNestedFive,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct InnerEntryNestedFive {
    deep: DeepEntryNestedFive,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct ResourceEntryNestedFive {
    inner: InnerEntryNestedFive,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct HyperEntryNestedSix {
    ticket: Resource<Ticket>,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct UltraEntryNestedSix {
    hyper: HyperEntryNestedSix,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct DeepestEntryNestedSix {
    ultra: UltraEntryNestedSix,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct DeeperEntryNestedSix {
    deepest: DeepestEntryNestedSix,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct DeepEntryNestedSix {
    deeper: DeeperEntryNestedSix,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct InnerEntryNestedSix {
    deep: DeepEntryNestedSix,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct ResourceEntryNestedSix {
    inner: InnerEntryNestedSix,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct LeftEntryMultipleNested {
    ticket: Resource<Ticket>,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct RightEntryMultipleNested {
    ticket: Resource<Ticket>,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct ResourceEntryMultipleNested {
    left: LeftEntryMultipleNested,
    right: RightEntryMultipleNested,
}

#[derive(
    Clone,
    Copy,
    Debug,
    PartialEq,
    wasmtime::component::ComponentType,
    wasmtime::component::Lift,
    wasmtime::component::Lower,
)]
#[component(enum)]
#[repr(u8)]
#[allow(dead_code)]
enum ErrorCode {
    #[component(name = "io")]
    Io,
    #[component(name = "no-entry")]
    NoEntry,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum CompletionMode {
    Pending,
    Ready,
    Error,
}

#[derive(Default)]
struct Stats {
    entries: Vec<u32>,
    multi_entries: Vec<(u32, u32, u32)>,
    stream_read_calls: u32,
    completion_polls: u32,
    pending_wakes: u32,
    stream_drops: u32,
    future_drops: u32,
    resource_created: u32,
    resource_drops: u32,
    eof: bool,
}

struct State {
    table: ResourceTable,
    stats: Arc<Mutex<Stats>>,
}

struct ProbeStream {
    stats: Arc<Mutex<Stats>>,
    entries: VecDeque<(u32, u32)>,
}

impl StreamProducer<State> for ProbeStream {
    type Item = ResourceEntry;
    type Buffer = VecBuffer<ResourceEntry>;

    fn poll_produce<'a>(
        self: Pin<&mut Self>,
        _cx: &mut TaskContext<'_>,
        mut store: StoreContextMut<'a, State>,
        mut destination: Destination<'a, Self::Item, Self::Buffer>,
        finish: bool,
    ) -> Poll<wasmtime::Result<StreamResult>> {
        if finish {
            return Poll::Ready(Ok(StreamResult::Cancelled));
        }
        let stream = self.get_mut();
        stream
            .stats
            .lock()
            .expect("record resource stats mutex poisoned")
            .stream_read_calls += 1;
        let Some((id, value)) = stream.entries.pop_front() else {
            stream
                .stats
                .lock()
                .expect("record resource stats mutex poisoned")
                .eof = true;
            destination.set_buffer(Vec::new().into());
            return Poll::Ready(Ok(StreamResult::Dropped));
        };
        let ticket = match store.data_mut().table.push(Ticket { _value: value }) {
            Ok(resource) => resource,
            Err(error) => return Poll::Ready(Err(error.into())),
        };
        stream
            .stats
            .lock()
            .expect("record resource stats mutex poisoned")
            .entries
            .push(id);
        stream
            .stats
            .lock()
            .expect("record resource stats mutex poisoned")
            .resource_created += 1;
        destination.set_buffer(vec![ResourceEntry { id, ticket }].into());
        Poll::Ready(Ok(StreamResult::Completed))
    }
}

impl Drop for ProbeStream {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("record resource stats mutex poisoned")
            .stream_drops += 1;
    }
}

struct ProbeStreamMulti {
    stats: Arc<Mutex<Stats>>,
    entries: VecDeque<(u32, u32, u32)>,
}

impl StreamProducer<State> for ProbeStreamMulti {
    type Item = ResourceEntryMulti;
    type Buffer = VecBuffer<ResourceEntryMulti>;

    fn poll_produce<'a>(
        self: Pin<&mut Self>,
        _cx: &mut TaskContext<'_>,
        mut store: StoreContextMut<'a, State>,
        mut destination: Destination<'a, Self::Item, Self::Buffer>,
        finish: bool,
    ) -> Poll<wasmtime::Result<StreamResult>> {
        if finish {
            return Poll::Ready(Ok(StreamResult::Cancelled));
        }
        let stream = self.get_mut();
        stream
            .stats
            .lock()
            .expect("multi record resource stats mutex poisoned")
            .stream_read_calls += 1;
        let Some((id, left_value, right_value)) = stream.entries.pop_front() else {
            stream
                .stats
                .lock()
                .expect("multi record resource stats mutex poisoned")
                .eof = true;
            destination.set_buffer(Vec::new().into());
            return Poll::Ready(Ok(StreamResult::Dropped));
        };
        let left = match store.data_mut().table.push(Ticket { _value: left_value }) {
            Ok(resource) => resource,
            Err(error) => return Poll::Ready(Err(error.into())),
        };
        let right = match store.data_mut().table.push(Ticket {
            _value: right_value,
        }) {
            Ok(resource) => resource,
            Err(error) => return Poll::Ready(Err(error.into())),
        };
        {
            let mut stats = stream
                .stats
                .lock()
                .expect("multi record resource stats mutex poisoned");
            stats.multi_entries.push((id, left_value, right_value));
            stats.resource_created += 2;
        }
        destination.set_buffer(vec![ResourceEntryMulti { id, left, right }].into());
        Poll::Ready(Ok(StreamResult::Completed))
    }
}

impl Drop for ProbeStreamMulti {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("multi record resource stats mutex poisoned")
            .stream_drops += 1;
    }
}

struct ProbeStreamNested {
    stats: Arc<Mutex<Stats>>,
    entries: VecDeque<u32>,
}

impl StreamProducer<State> for ProbeStreamNested {
    type Item = ResourceEntryNested;
    type Buffer = VecBuffer<ResourceEntryNested>;

    fn poll_produce<'a>(
        self: Pin<&mut Self>,
        _cx: &mut TaskContext<'_>,
        mut store: StoreContextMut<'a, State>,
        mut destination: Destination<'a, Self::Item, Self::Buffer>,
        finish: bool,
    ) -> Poll<wasmtime::Result<StreamResult>> {
        if finish {
            return Poll::Ready(Ok(StreamResult::Cancelled));
        }
        let stream = self.get_mut();
        stream
            .stats
            .lock()
            .expect("nested record resource stats mutex poisoned")
            .stream_read_calls += 1;
        let Some(value) = stream.entries.pop_front() else {
            stream
                .stats
                .lock()
                .expect("nested record resource stats mutex poisoned")
                .eof = true;
            destination.set_buffer(Vec::new().into());
            return Poll::Ready(Ok(StreamResult::Dropped));
        };
        let ticket = match store.data_mut().table.push(Ticket { _value: value }) {
            Ok(resource) => resource,
            Err(error) => return Poll::Ready(Err(error.into())),
        };
        {
            let mut stats = stream
                .stats
                .lock()
                .expect("nested record resource stats mutex poisoned");
            stats.entries.push(value);
            stats.resource_created += 1;
        }
        destination.set_buffer(
            vec![ResourceEntryNested {
                inner: InnerEntry { ticket },
            }]
            .into(),
        );
        Poll::Ready(Ok(StreamResult::Completed))
    }
}

impl Drop for ProbeStreamNested {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("nested record resource stats mutex poisoned")
            .stream_drops += 1;
    }
}

struct ProbeStreamNestedTwo {
    stats: Arc<Mutex<Stats>>,
    entries: VecDeque<u32>,
}

impl StreamProducer<State> for ProbeStreamNestedTwo {
    type Item = ResourceEntryNestedTwo;
    type Buffer = VecBuffer<ResourceEntryNestedTwo>;

    fn poll_produce<'a>(
        self: Pin<&mut Self>,
        _cx: &mut TaskContext<'_>,
        mut store: StoreContextMut<'a, State>,
        mut destination: Destination<'a, Self::Item, Self::Buffer>,
        finish: bool,
    ) -> Poll<wasmtime::Result<StreamResult>> {
        if finish {
            return Poll::Ready(Ok(StreamResult::Cancelled));
        }
        let stream = self.get_mut();
        stream
            .stats
            .lock()
            .expect("two-level nested record resource stats mutex poisoned")
            .stream_read_calls += 1;
        let Some(value) = stream.entries.pop_front() else {
            stream
                .stats
                .lock()
                .expect("two-level nested record resource stats mutex poisoned")
                .eof = true;
            destination.set_buffer(Vec::new().into());
            return Poll::Ready(Ok(StreamResult::Dropped));
        };
        let ticket = match store.data_mut().table.push(Ticket { _value: value }) {
            Ok(resource) => resource,
            Err(error) => return Poll::Ready(Err(error.into())),
        };
        {
            let mut stats = stream
                .stats
                .lock()
                .expect("two-level nested record resource stats mutex poisoned");
            stats.entries.push(value);
            stats.resource_created += 1;
        }
        destination.set_buffer(
            vec![ResourceEntryNestedTwo {
                inner: InnerEntryNestedTwo {
                    deep: DeepEntry { ticket },
                },
            }]
            .into(),
        );
        Poll::Ready(Ok(StreamResult::Completed))
    }
}

impl Drop for ProbeStreamNestedTwo {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("two-level nested record resource stats mutex poisoned")
            .stream_drops += 1;
    }
}

struct ProbeStreamNestedThree {
    stats: Arc<Mutex<Stats>>,
    entries: VecDeque<u32>,
}

impl StreamProducer<State> for ProbeStreamNestedThree {
    type Item = ResourceEntryNestedThree;
    type Buffer = VecBuffer<ResourceEntryNestedThree>;

    fn poll_produce<'a>(
        self: Pin<&mut Self>,
        _cx: &mut TaskContext<'_>,
        mut store: StoreContextMut<'a, State>,
        mut destination: Destination<'a, Self::Item, Self::Buffer>,
        finish: bool,
    ) -> Poll<wasmtime::Result<StreamResult>> {
        if finish {
            return Poll::Ready(Ok(StreamResult::Cancelled));
        }
        let stream = self.get_mut();
        stream
            .stats
            .lock()
            .expect("three-level nested record resource stats mutex poisoned")
            .stream_read_calls += 1;
        let Some(value) = stream.entries.pop_front() else {
            stream
                .stats
                .lock()
                .expect("three-level nested record resource stats mutex poisoned")
                .eof = true;
            destination.set_buffer(Vec::new().into());
            return Poll::Ready(Ok(StreamResult::Dropped));
        };
        let ticket = match store.data_mut().table.push(Ticket { _value: value }) {
            Ok(resource) => resource,
            Err(error) => return Poll::Ready(Err(error.into())),
        };
        {
            let mut stats = stream
                .stats
                .lock()
                .expect("three-level nested record resource stats mutex poisoned");
            stats.entries.push(value);
            stats.resource_created += 1;
        }
        destination.set_buffer(
            vec![ResourceEntryNestedThree {
                inner: InnerEntryNestedThree {
                    deep: DeepEntryNestedThree {
                        deeper: DeeperEntryNestedThree { ticket },
                    },
                },
            }]
            .into(),
        );
        Poll::Ready(Ok(StreamResult::Completed))
    }
}

impl Drop for ProbeStreamNestedThree {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("three-level nested record resource stats mutex poisoned")
            .stream_drops += 1;
    }
}

struct ProbeStreamNestedFour {
    stats: Arc<Mutex<Stats>>,
    entries: VecDeque<u32>,
}

impl StreamProducer<State> for ProbeStreamNestedFour {
    type Item = ResourceEntryNestedFour;
    type Buffer = VecBuffer<ResourceEntryNestedFour>;

    fn poll_produce<'a>(
        self: Pin<&mut Self>,
        _cx: &mut TaskContext<'_>,
        mut store: StoreContextMut<'a, State>,
        mut destination: Destination<'a, Self::Item, Self::Buffer>,
        finish: bool,
    ) -> Poll<wasmtime::Result<StreamResult>> {
        if finish {
            return Poll::Ready(Ok(StreamResult::Cancelled));
        }
        let stream = self.get_mut();
        stream
            .stats
            .lock()
            .expect("four-level nested record resource stats mutex poisoned")
            .stream_read_calls += 1;
        let Some(value) = stream.entries.pop_front() else {
            stream
                .stats
                .lock()
                .expect("four-level nested record resource stats mutex poisoned")
                .eof = true;
            destination.set_buffer(Vec::new().into());
            return Poll::Ready(Ok(StreamResult::Dropped));
        };
        let ticket = match store.data_mut().table.push(Ticket { _value: value }) {
            Ok(resource) => resource,
            Err(error) => return Poll::Ready(Err(error.into())),
        };
        {
            let mut stats = stream
                .stats
                .lock()
                .expect("four-level nested record resource stats mutex poisoned");
            stats.entries.push(value);
            stats.resource_created += 1;
        }
        destination.set_buffer(
            vec![ResourceEntryNestedFour {
                inner: InnerEntryNestedFour {
                    deep: DeepEntryNestedFour {
                        deeper: DeeperEntryNestedFour {
                            deepest: DeepestEntryNestedFour { ticket },
                        },
                    },
                },
            }]
            .into(),
        );
        Poll::Ready(Ok(StreamResult::Completed))
    }
}

impl Drop for ProbeStreamNestedFour {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("four-level nested record resource stats mutex poisoned")
            .stream_drops += 1;
    }
}

struct ProbeStreamNestedFive {
    stats: Arc<Mutex<Stats>>,
    entries: VecDeque<u32>,
}

impl StreamProducer<State> for ProbeStreamNestedFive {
    type Item = ResourceEntryNestedFive;
    type Buffer = VecBuffer<ResourceEntryNestedFive>;

    fn poll_produce<'a>(
        self: Pin<&mut Self>,
        _cx: &mut TaskContext<'_>,
        mut store: StoreContextMut<'a, State>,
        mut destination: Destination<'a, Self::Item, Self::Buffer>,
        finish: bool,
    ) -> Poll<wasmtime::Result<StreamResult>> {
        if finish {
            return Poll::Ready(Ok(StreamResult::Cancelled));
        }
        let stream = self.get_mut();
        stream
            .stats
            .lock()
            .expect("five-level nested record resource stats mutex poisoned")
            .stream_read_calls += 1;
        let Some(value) = stream.entries.pop_front() else {
            stream
                .stats
                .lock()
                .expect("five-level nested record resource stats mutex poisoned")
                .eof = true;
            destination.set_buffer(Vec::new().into());
            return Poll::Ready(Ok(StreamResult::Dropped));
        };
        let ticket = match store.data_mut().table.push(Ticket { _value: value }) {
            Ok(resource) => resource,
            Err(error) => return Poll::Ready(Err(error.into())),
        };
        {
            let mut stats = stream
                .stats
                .lock()
                .expect("five-level nested record resource stats mutex poisoned");
            stats.entries.push(value);
            stats.resource_created += 1;
        }
        destination.set_buffer(
            vec![ResourceEntryNestedFive {
                inner: InnerEntryNestedFive {
                    deep: DeepEntryNestedFive {
                        deeper: DeeperEntryNestedFive {
                            deepest: DeepestEntryNestedFive {
                                ultra: UltraEntryNestedFive { ticket },
                            },
                        },
                    },
                },
            }]
            .into(),
        );
        Poll::Ready(Ok(StreamResult::Completed))
    }
}

impl Drop for ProbeStreamNestedFive {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("five-level nested record resource stats mutex poisoned")
            .stream_drops += 1;
    }
}

struct ProbeStreamNestedSix {
    stats: Arc<Mutex<Stats>>,
    entries: VecDeque<u32>,
}

impl StreamProducer<State> for ProbeStreamNestedSix {
    type Item = ResourceEntryNestedSix;
    type Buffer = VecBuffer<ResourceEntryNestedSix>;

    fn poll_produce<'a>(
        self: Pin<&mut Self>,
        _cx: &mut TaskContext<'_>,
        mut store: StoreContextMut<'a, State>,
        mut destination: Destination<'a, Self::Item, Self::Buffer>,
        finish: bool,
    ) -> Poll<wasmtime::Result<StreamResult>> {
        if finish {
            return Poll::Ready(Ok(StreamResult::Cancelled));
        }
        let stream = self.get_mut();
        stream
            .stats
            .lock()
            .expect("six-level nested record resource stats mutex poisoned")
            .stream_read_calls += 1;
        let Some(value) = stream.entries.pop_front() else {
            stream
                .stats
                .lock()
                .expect("six-level nested record resource stats mutex poisoned")
                .eof = true;
            destination.set_buffer(Vec::new().into());
            return Poll::Ready(Ok(StreamResult::Dropped));
        };
        let ticket = match store.data_mut().table.push(Ticket { _value: value }) {
            Ok(resource) => resource,
            Err(error) => return Poll::Ready(Err(error.into())),
        };
        {
            let mut stats = stream
                .stats
                .lock()
                .expect("six-level nested record resource stats mutex poisoned");
            stats.entries.push(value);
            stats.resource_created += 1;
        }
        destination.set_buffer(
            vec![ResourceEntryNestedSix {
                inner: InnerEntryNestedSix {
                    deep: DeepEntryNestedSix {
                        deeper: DeeperEntryNestedSix {
                            deepest: DeepestEntryNestedSix {
                                ultra: UltraEntryNestedSix {
                                    hyper: HyperEntryNestedSix { ticket },
                                },
                            },
                        },
                    },
                },
            }]
            .into(),
        );
        Poll::Ready(Ok(StreamResult::Completed))
    }
}

impl Drop for ProbeStreamNestedSix {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("six-level nested record resource stats mutex poisoned")
            .stream_drops += 1;
    }
}

struct ProbeStreamMultipleNested {
    stats: Arc<Mutex<Stats>>,
    entries: VecDeque<(u32, u32, u32)>,
}

impl StreamProducer<State> for ProbeStreamMultipleNested {
    type Item = ResourceEntryMultipleNested;
    type Buffer = VecBuffer<ResourceEntryMultipleNested>;

    fn poll_produce<'a>(
        self: Pin<&mut Self>,
        _cx: &mut TaskContext<'_>,
        mut store: StoreContextMut<'a, State>,
        mut destination: Destination<'a, Self::Item, Self::Buffer>,
        finish: bool,
    ) -> Poll<wasmtime::Result<StreamResult>> {
        if finish {
            return Poll::Ready(Ok(StreamResult::Cancelled));
        }
        let stream = self.get_mut();
        stream
            .stats
            .lock()
            .expect("multiple-nested record resource stats mutex poisoned")
            .stream_read_calls += 1;
        let Some((id, left_value, right_value)) = stream.entries.pop_front() else {
            stream
                .stats
                .lock()
                .expect("multiple-nested record resource stats mutex poisoned")
                .eof = true;
            destination.set_buffer(Vec::new().into());
            return Poll::Ready(Ok(StreamResult::Dropped));
        };
        let left = match store.data_mut().table.push(Ticket { _value: left_value }) {
            Ok(resource) => resource,
            Err(error) => return Poll::Ready(Err(error.into())),
        };
        let right = match store.data_mut().table.push(Ticket {
            _value: right_value,
        }) {
            Ok(resource) => resource,
            Err(error) => return Poll::Ready(Err(error.into())),
        };
        {
            let mut stats = stream
                .stats
                .lock()
                .expect("multiple-nested record resource stats mutex poisoned");
            stats.multi_entries.push((id, left_value, right_value));
            stats.resource_created += 2;
        }
        destination.set_buffer(
            vec![ResourceEntryMultipleNested {
                left: LeftEntryMultipleNested { ticket: left },
                right: RightEntryMultipleNested { ticket: right },
            }]
            .into(),
        );
        Poll::Ready(Ok(StreamResult::Completed))
    }
}

impl Drop for ProbeStreamMultipleNested {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("multiple-nested record resource stats mutex poisoned")
            .stream_drops += 1;
    }
}

struct ProbeCompletion {
    stats: Arc<Mutex<Stats>>,
    mode: CompletionMode,
    polled: bool,
}

impl Future for ProbeCompletion {
    type Output = wasmtime::Result<std::result::Result<(), ErrorCode>>;

    fn poll(mut self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        self.stats
            .lock()
            .expect("record resource completion stats mutex poisoned")
            .completion_polls += 1;
        if self.mode == CompletionMode::Pending && !self.polled {
            self.polled = true;
            self.stats
                .lock()
                .expect("record resource completion stats mutex poisoned")
                .pending_wakes += 1;
            cx.waker().wake_by_ref();
            return Poll::Pending;
        }
        self.polled = true;
        if self.mode == CompletionMode::Error {
            Poll::Ready(Ok(Err(ErrorCode::Io)))
        } else {
            Poll::Ready(Ok(Ok(())))
        }
    }
}

impl Drop for ProbeCompletion {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("record resource completion stats mutex poisoned")
            .future_drops += 1;
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn install_source(
    linker: &mut Linker<State>,
    stats: Arc<Mutex<Stats>>,
    mode: CompletionMode,
) -> wasmtime::Result<()> {
    let mut source = linker.instance(SOURCE_INSTANCE)?;
    source.resource(
        "ticket",
        ResourceType::host::<Ticket>(),
        |mut store, rep| {
            let state = store.data_mut();
            state
                .stats
                .lock()
                .expect("record resource drop stats mutex poisoned")
                .resource_drops += 1;
            let resource = Resource::<Ticket>::new_own(rep);
            let _ = state.table.delete(resource)?;
            Ok(())
        },
    )?;
    source.func_wrap("read-via-stream", move |mut store, ()| {
        let stats = Arc::clone(&stats);
        let reader = StreamReader::new(
            &mut store,
            ProbeStream {
                stats: Arc::clone(&stats),
                entries: VecDeque::from([(1, 111), (2, 222)]),
            },
        )?;
        let completion = FutureReader::new(
            &mut store,
            ProbeCompletion {
                stats,
                mode,
                polled: false,
            },
        )?;
        Ok(((reader, completion),))
    })?;
    Ok(())
}

fn install_source_multi(
    linker: &mut Linker<State>,
    stats: Arc<Mutex<Stats>>,
    mode: CompletionMode,
) -> wasmtime::Result<()> {
    let mut source = linker.instance(SOURCE_MULTI_INSTANCE)?;
    source.resource(
        "ticket",
        ResourceType::host::<Ticket>(),
        |mut store, rep| {
            let state = store.data_mut();
            state
                .stats
                .lock()
                .expect("multi record resource drop stats mutex poisoned")
                .resource_drops += 1;
            let resource = Resource::<Ticket>::new_own(rep);
            let _ = state.table.delete(resource)?;
            Ok(())
        },
    )?;
    source.func_wrap("read-via-stream", move |mut store, ()| {
        let stats = Arc::clone(&stats);
        let reader = StreamReader::new(
            &mut store,
            ProbeStreamMulti {
                stats: Arc::clone(&stats),
                entries: VecDeque::from([(1, 111, 222), (2, 333, 444)]),
            },
        )?;
        let completion = FutureReader::new(
            &mut store,
            ProbeCompletion {
                stats,
                mode,
                polled: false,
            },
        )?;
        Ok(((reader, completion),))
    })?;
    Ok(())
}

fn install_source_nested(
    linker: &mut Linker<State>,
    stats: Arc<Mutex<Stats>>,
    mode: CompletionMode,
) -> wasmtime::Result<()> {
    let mut source = linker.instance(SOURCE_NESTED_INSTANCE)?;
    source.resource(
        "ticket",
        ResourceType::host::<Ticket>(),
        |mut store, rep| {
            let state = store.data_mut();
            state
                .stats
                .lock()
                .expect("nested record resource drop stats mutex poisoned")
                .resource_drops += 1;
            let resource = Resource::<Ticket>::new_own(rep);
            let _ = state.table.delete(resource)?;
            Ok(())
        },
    )?;
    source.func_wrap("read-via-stream", move |mut store, ()| {
        let stats = Arc::clone(&stats);
        let reader = StreamReader::new(
            &mut store,
            ProbeStreamNested {
                stats: Arc::clone(&stats),
                entries: VecDeque::from([111, 222]),
            },
        )?;
        let completion = FutureReader::new(
            &mut store,
            ProbeCompletion {
                stats,
                mode,
                polled: false,
            },
        )?;
        Ok(((reader, completion),))
    })?;
    Ok(())
}

fn install_source_nested_two(
    linker: &mut Linker<State>,
    stats: Arc<Mutex<Stats>>,
    mode: CompletionMode,
) -> wasmtime::Result<()> {
    let mut source = linker.instance(SOURCE_NESTED_TWO_INSTANCE)?;
    source.resource(
        "ticket",
        ResourceType::host::<Ticket>(),
        |mut store, rep| {
            let state = store.data_mut();
            state
                .stats
                .lock()
                .expect("two-level nested record resource drop stats mutex poisoned")
                .resource_drops += 1;
            let resource = Resource::<Ticket>::new_own(rep);
            let _ = state.table.delete(resource)?;
            Ok(())
        },
    )?;
    source.func_wrap("read-via-stream", move |mut store, ()| {
        let stats = Arc::clone(&stats);
        let reader = StreamReader::new(
            &mut store,
            ProbeStreamNestedTwo {
                stats: Arc::clone(&stats),
                entries: VecDeque::from([111, 222]),
            },
        )?;
        let completion = FutureReader::new(
            &mut store,
            ProbeCompletion {
                stats,
                mode,
                polled: false,
            },
        )?;
        Ok(((reader, completion),))
    })?;
    Ok(())
}

fn install_source_nested_three(
    linker: &mut Linker<State>,
    stats: Arc<Mutex<Stats>>,
    mode: CompletionMode,
) -> wasmtime::Result<()> {
    let mut source = linker.instance(SOURCE_NESTED_THREE_INSTANCE)?;
    source.resource(
        "ticket",
        ResourceType::host::<Ticket>(),
        |mut store, rep| {
            let state = store.data_mut();
            state
                .stats
                .lock()
                .expect("three-level nested record resource drop stats mutex poisoned")
                .resource_drops += 1;
            let resource = Resource::<Ticket>::new_own(rep);
            let _ = state.table.delete(resource)?;
            Ok(())
        },
    )?;
    source.func_wrap("read-via-stream", move |mut store, ()| {
        let stats = Arc::clone(&stats);
        let reader = StreamReader::new(
            &mut store,
            ProbeStreamNestedThree {
                stats: Arc::clone(&stats),
                entries: VecDeque::from([111, 222]),
            },
        )?;
        let completion = FutureReader::new(
            &mut store,
            ProbeCompletion {
                stats,
                mode,
                polled: false,
            },
        )?;
        Ok(((reader, completion),))
    })?;
    Ok(())
}

fn install_source_nested_four(
    linker: &mut Linker<State>,
    stats: Arc<Mutex<Stats>>,
    mode: CompletionMode,
) -> wasmtime::Result<()> {
    let mut source = linker.instance(SOURCE_NESTED_FOUR_INSTANCE)?;
    source.resource(
        "ticket",
        ResourceType::host::<Ticket>(),
        |mut store, rep| {
            let state = store.data_mut();
            state
                .stats
                .lock()
                .expect("four-level nested record resource drop stats mutex poisoned")
                .resource_drops += 1;
            let resource = Resource::<Ticket>::new_own(rep);
            let _ = state.table.delete(resource)?;
            Ok(())
        },
    )?;
    source.func_wrap("read-via-stream", move |mut store, ()| {
        let stats = Arc::clone(&stats);
        let reader = StreamReader::new(
            &mut store,
            ProbeStreamNestedFour {
                stats: Arc::clone(&stats),
                entries: VecDeque::from([111, 222]),
            },
        )?;
        let completion = FutureReader::new(
            &mut store,
            ProbeCompletion {
                stats,
                mode,
                polled: false,
            },
        )?;
        Ok(((reader, completion),))
    })?;
    Ok(())
}

fn install_source_nested_five(
    linker: &mut Linker<State>,
    stats: Arc<Mutex<Stats>>,
    mode: CompletionMode,
) -> wasmtime::Result<()> {
    let mut source = linker.instance(SOURCE_NESTED_FIVE_INSTANCE)?;
    source.resource(
        "ticket",
        ResourceType::host::<Ticket>(),
        |mut store, rep| {
            let state = store.data_mut();
            state
                .stats
                .lock()
                .expect("five-level nested record resource drop stats mutex poisoned")
                .resource_drops += 1;
            let resource = Resource::<Ticket>::new_own(rep);
            let _ = state.table.delete(resource)?;
            Ok(())
        },
    )?;
    source.func_wrap("read-via-stream", move |mut store, ()| {
        let stats = Arc::clone(&stats);
        let reader = StreamReader::new(
            &mut store,
            ProbeStreamNestedFive {
                stats: Arc::clone(&stats),
                entries: VecDeque::from([111, 222]),
            },
        )?;
        let completion = FutureReader::new(
            &mut store,
            ProbeCompletion {
                stats,
                mode,
                polled: false,
            },
        )?;
        Ok(((reader, completion),))
    })?;
    Ok(())
}

fn install_source_nested_six(
    linker: &mut Linker<State>,
    stats: Arc<Mutex<Stats>>,
    mode: CompletionMode,
) -> wasmtime::Result<()> {
    let mut source = linker.instance(SOURCE_NESTED_SIX_INSTANCE)?;
    source.resource(
        "ticket",
        ResourceType::host::<Ticket>(),
        |mut store, rep| {
            let state = store.data_mut();
            state
                .stats
                .lock()
                .expect("six-level nested record resource drop stats mutex poisoned")
                .resource_drops += 1;
            let resource = Resource::<Ticket>::new_own(rep);
            let _ = state.table.delete(resource)?;
            Ok(())
        },
    )?;
    source.func_wrap("read-via-stream", move |mut store, ()| {
        let stats = Arc::clone(&stats);
        let reader = StreamReader::new(
            &mut store,
            ProbeStreamNestedSix {
                stats: Arc::clone(&stats),
                entries: VecDeque::from([111, 222]),
            },
        )?;
        let completion = FutureReader::new(
            &mut store,
            ProbeCompletion {
                stats,
                mode,
                polled: false,
            },
        )?;
        Ok(((reader, completion),))
    })?;
    Ok(())
}

fn install_source_multiple_nested(
    linker: &mut Linker<State>,
    stats: Arc<Mutex<Stats>>,
    mode: CompletionMode,
) -> wasmtime::Result<()> {
    let mut source = linker.instance(SOURCE_MULTIPLE_NESTED_INSTANCE)?;
    source.resource(
        "ticket",
        ResourceType::host::<Ticket>(),
        |mut store, rep| {
            let state = store.data_mut();
            state
                .stats
                .lock()
                .expect("multiple-nested record resource drop stats mutex poisoned")
                .resource_drops += 1;
            let resource = Resource::<Ticket>::new_own(rep);
            let _ = state.table.delete(resource)?;
            Ok(())
        },
    )?;
    source.func_wrap("read-via-stream", move |mut store, ()| {
        let stats = Arc::clone(&stats);
        let reader = StreamReader::new(
            &mut store,
            ProbeStreamMultipleNested {
                stats: Arc::clone(&stats),
                entries: VecDeque::from([(1, 111, 222), (2, 333, 444)]),
            },
        )?;
        let completion = FutureReader::new(
            &mut store,
            ProbeCompletion {
                stats,
                mode,
                polled: false,
            },
        )?;
        Ok(((reader, completion),))
    })?;
    Ok(())
}

async fn run(component_path: &Path, mode: CompletionMode) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_component_model_async(true);
    config.wasm_component_model_more_async_builtins(true);
    config.concurrency_support(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, component_path))
        .with_context(|| format!("load component {}", component_path.display()))?;
    let stats = Arc::new(Mutex::new(Stats::default()));
    let mut linker = Linker::new(&engine);
    map_wasmtime(install_source(&mut linker, Arc::clone(&stats), mode))?;
    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
            stats: Arc::clone(&stats),
        },
    );
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let probe = instance
        .get_export_index(&mut store, None, PROBE_INSTANCE)
        .context("missing record resource probe export")?;
    let run = instance
        .get_export_index(&mut store, Some(&probe), "run")
        .context("missing record resource probe.run export")?;
    let run = map_wasmtime(
        instance.get_typed_func::<(), (std::result::Result<(), ErrorCode>,)>(&mut store, &run),
    )?;
    let call = map_wasmtime(
        store
            .run_concurrent(async |accessor| run.call_concurrent(&accessor, ()).await)
            .await,
    )?;
    let result = map_wasmtime(call)?;
    let expected_result = if mode == CompletionMode::Error {
        Err(ErrorCode::Io)
    } else {
        Ok(())
    };
    if result.0 != expected_result {
        bail!("unexpected result: {:?}", result.0);
    }
    let snapshot = stats.lock().expect("record resource stats mutex poisoned");
    let expected_polls = if mode == CompletionMode::Pending {
        2
    } else {
        1
    };
    if snapshot.entries != [1, 2]
        || snapshot.stream_read_calls != 3
        || !snapshot.eof
        || snapshot.completion_polls != expected_polls
        || snapshot.pending_wakes != u32::from(mode == CompletionMode::Pending)
        || snapshot.stream_drops != 1
        || snapshot.future_drops != 1
        || snapshot.resource_created != 2
        || snapshot.resource_drops != 2
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected record resource stats: entries={:?} reads={} eof={} completion-polls={} pending-wakes={} stream-drops={} future-drops={} resource-created={} resource-drops={} table-empty={}",
            snapshot.entries,
            snapshot.stream_read_calls,
            snapshot.eof,
            snapshot.completion_polls,
            snapshot.pending_wakes,
            snapshot.stream_drops,
            snapshot.future_drops,
            snapshot.resource_created,
            snapshot.resource_drops,
            store.data().table.is_empty(),
        );
    }
    println!(
        "Rust generic record-resource stream {} passed entries=[(1,111),(2,222)] eof=true stream-reads=3 completion-polls={} pending-wakes={} resource-created=2 resource-drops=2 stream-drops=1 future-drops=1 table-empty=true result={}",
        match mode {
            CompletionMode::Pending => "pending",
            CompletionMode::Ready => "ready",
            CompletionMode::Error => "error",
        },
        snapshot.completion_polls,
        snapshot.pending_wakes,
        if mode == CompletionMode::Error {
            "Err(io)"
        } else {
            "Ok"
        },
    );
    Ok(())
}

async fn run_multi(component_path: &Path, mode: CompletionMode) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_component_model_async(true);
    config.wasm_component_model_more_async_builtins(true);
    config.concurrency_support(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, component_path))
        .with_context(|| format!("load multi-resource component {}", component_path.display()))?;
    let stats = Arc::new(Mutex::new(Stats::default()));
    let mut linker = Linker::new(&engine);
    map_wasmtime(install_source_multi(&mut linker, Arc::clone(&stats), mode))?;
    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
            stats: Arc::clone(&stats),
        },
    );
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let probe = instance
        .get_export_index(&mut store, None, PROBE_MULTI_INSTANCE)
        .context("missing multi-resource record stream probe export")?;
    let run = instance
        .get_export_index(&mut store, Some(&probe), "run")
        .context("missing multi-resource record stream probe.run export")?;
    let run = map_wasmtime(
        instance.get_typed_func::<(), (std::result::Result<(), ErrorCode>,)>(&mut store, &run),
    )?;
    let call = map_wasmtime(
        store
            .run_concurrent(async |accessor| run.call_concurrent(&accessor, ()).await)
            .await,
    )?;
    let result = map_wasmtime(call)?;
    let expected_result = if mode == CompletionMode::Error {
        Err(ErrorCode::Io)
    } else {
        Ok(())
    };
    if result.0 != expected_result {
        bail!("unexpected multi-resource result: {:?}", result.0);
    }
    let snapshot = stats
        .lock()
        .expect("multi record resource stats mutex poisoned");
    let expected_polls = if mode == CompletionMode::Pending {
        2
    } else {
        1
    };
    if snapshot.multi_entries != [(1, 111, 222), (2, 333, 444)]
        || snapshot.stream_read_calls != 3
        || !snapshot.eof
        || snapshot.completion_polls != expected_polls
        || snapshot.pending_wakes != u32::from(mode == CompletionMode::Pending)
        || snapshot.stream_drops != 1
        || snapshot.future_drops != 1
        || snapshot.resource_created != 4
        || snapshot.resource_drops != 4
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected multi-resource stats: entries={:?} reads={} eof={} completion-polls={} pending-wakes={} stream-drops={} future-drops={} resource-created={} resource-drops={} table-empty={}",
            snapshot.multi_entries,
            snapshot.stream_read_calls,
            snapshot.eof,
            snapshot.completion_polls,
            snapshot.pending_wakes,
            snapshot.stream_drops,
            snapshot.future_drops,
            snapshot.resource_created,
            snapshot.resource_drops,
            store.data().table.is_empty(),
        );
    }
    println!(
        "Rust generic multi-resource record-stream {} passed entries=[(1,111,222),(2,333,444)] eof=true stream-reads=3 completion-polls={} pending-wakes={} resource-created=4 resource-drops=4 stream-drops=1 future-drops=1 table-empty=true result={}",
        match mode {
            CompletionMode::Pending => "pending",
            CompletionMode::Ready => "ready",
            CompletionMode::Error => "error",
        },
        snapshot.completion_polls,
        snapshot.pending_wakes,
        if mode == CompletionMode::Error {
            "Err(io)"
        } else {
            "Ok"
        },
    );
    Ok(())
}

async fn run_nested(component_path: &Path, mode: CompletionMode) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_component_model_async(true);
    config.wasm_component_model_more_async_builtins(true);
    config.concurrency_support(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component =
        map_wasmtime(Component::from_file(&engine, component_path)).with_context(|| {
            format!(
                "load nested-resource component {}",
                component_path.display()
            )
        })?;
    let stats = Arc::new(Mutex::new(Stats::default()));
    let mut linker = Linker::new(&engine);
    map_wasmtime(install_source_nested(&mut linker, Arc::clone(&stats), mode))?;
    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
            stats: Arc::clone(&stats),
        },
    );
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let probe = instance
        .get_export_index(&mut store, None, PROBE_NESTED_INSTANCE)
        .context("missing nested-resource record stream probe export")?;
    let run = instance
        .get_export_index(&mut store, Some(&probe), "run")
        .context("missing nested-resource record stream probe.run export")?;
    let run = map_wasmtime(
        instance.get_typed_func::<(), (std::result::Result<(), ErrorCode>,)>(&mut store, &run),
    )?;
    let call = map_wasmtime(
        store
            .run_concurrent(async |accessor| run.call_concurrent(&accessor, ()).await)
            .await,
    )?;
    let result = map_wasmtime(call)?;
    let expected_result = if mode == CompletionMode::Error {
        Err(ErrorCode::Io)
    } else {
        Ok(())
    };
    if result.0 != expected_result {
        bail!("unexpected nested-resource result: {:?}", result.0);
    }
    let snapshot = stats
        .lock()
        .expect("nested record resource stats mutex poisoned");
    let expected_polls = if mode == CompletionMode::Pending {
        2
    } else {
        1
    };
    if snapshot.entries != [111, 222]
        || snapshot.stream_read_calls != 3
        || !snapshot.eof
        || snapshot.completion_polls != expected_polls
        || snapshot.pending_wakes != u32::from(mode == CompletionMode::Pending)
        || snapshot.stream_drops != 1
        || snapshot.future_drops != 1
        || snapshot.resource_created != 2
        || snapshot.resource_drops != 2
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected nested-resource stats: entries={:?} reads={} eof={} completion-polls={} pending-wakes={} stream-drops={} future-drops={} resource-created={} resource-drops={} table-empty={}",
            snapshot.entries,
            snapshot.stream_read_calls,
            snapshot.eof,
            snapshot.completion_polls,
            snapshot.pending_wakes,
            snapshot.stream_drops,
            snapshot.future_drops,
            snapshot.resource_created,
            snapshot.resource_drops,
            store.data().table.is_empty(),
        );
    }
    println!(
        "Rust generic nested-resource record-stream {} passed entries=[111,222] eof=true stream-reads=3 completion-polls={} pending-wakes={} resource-created=2 resource-drops=2 stream-drops=1 future-drops=1 table-empty=true result={}",
        match mode {
            CompletionMode::Pending => "pending",
            CompletionMode::Ready => "ready",
            CompletionMode::Error => "error",
        },
        snapshot.completion_polls,
        snapshot.pending_wakes,
        if mode == CompletionMode::Error {
            "Err(io)"
        } else {
            "Ok"
        },
    );
    Ok(())
}

async fn run_nested_two(component_path: &Path, mode: CompletionMode) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_component_model_async(true);
    config.wasm_component_model_more_async_builtins(true);
    config.concurrency_support(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component =
        map_wasmtime(Component::from_file(&engine, component_path)).with_context(|| {
            format!(
                "load two-level nested-resource component {}",
                component_path.display()
            )
        })?;
    let stats = Arc::new(Mutex::new(Stats::default()));
    let mut linker = Linker::new(&engine);
    map_wasmtime(install_source_nested_two(
        &mut linker,
        Arc::clone(&stats),
        mode,
    ))?;
    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
            stats: Arc::clone(&stats),
        },
    );
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let probe = instance
        .get_export_index(&mut store, None, PROBE_NESTED_TWO_INSTANCE)
        .context("missing two-level nested-resource record stream probe export")?;
    let run = instance
        .get_export_index(&mut store, Some(&probe), "run")
        .context("missing two-level nested-resource record stream probe.run export")?;
    let run = map_wasmtime(
        instance.get_typed_func::<(), (std::result::Result<(), ErrorCode>,)>(&mut store, &run),
    )?;
    let call = map_wasmtime(
        store
            .run_concurrent(async |accessor| run.call_concurrent(&accessor, ()).await)
            .await,
    )?;
    let result = map_wasmtime(call)?;
    let expected_result = if mode == CompletionMode::Error {
        Err(ErrorCode::Io)
    } else {
        Ok(())
    };
    if result.0 != expected_result {
        bail!(
            "unexpected two-level nested-resource result: {:?}",
            result.0
        );
    }
    let snapshot = stats
        .lock()
        .expect("two-level nested record resource stats mutex poisoned");
    let expected_polls = if mode == CompletionMode::Pending {
        2
    } else {
        1
    };
    if snapshot.entries != [111, 222]
        || snapshot.stream_read_calls != 3
        || !snapshot.eof
        || snapshot.completion_polls != expected_polls
        || snapshot.pending_wakes != u32::from(mode == CompletionMode::Pending)
        || snapshot.stream_drops != 1
        || snapshot.future_drops != 1
        || snapshot.resource_created != 2
        || snapshot.resource_drops != 2
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected two-level nested-resource stats: entries={:?} reads={} eof={} completion-polls={} pending-wakes={} stream-drops={} future-drops={} resource-created={} resource-drops={} table-empty={}",
            snapshot.entries,
            snapshot.stream_read_calls,
            snapshot.eof,
            snapshot.completion_polls,
            snapshot.pending_wakes,
            snapshot.stream_drops,
            snapshot.future_drops,
            snapshot.resource_created,
            snapshot.resource_drops,
            store.data().table.is_empty(),
        );
    }
    println!(
        "Rust generic two-level nested-resource record-stream {} passed entries=[111,222] eof=true stream-reads=3 completion-polls={} pending-wakes={} resource-created=2 resource-drops=2 stream-drops=1 future-drops=1 table-empty=true result={}",
        match mode {
            CompletionMode::Pending => "pending",
            CompletionMode::Ready => "ready",
            CompletionMode::Error => "error",
        },
        snapshot.completion_polls,
        snapshot.pending_wakes,
        if mode == CompletionMode::Error {
            "Err(io)"
        } else {
            "Ok"
        },
    );
    Ok(())
}

async fn run_nested_three(component_path: &Path, mode: CompletionMode) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_component_model_async(true);
    config.wasm_component_model_more_async_builtins(true);
    config.concurrency_support(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component =
        map_wasmtime(Component::from_file(&engine, component_path)).with_context(|| {
            format!(
                "load three-level nested-resource component {}",
                component_path.display()
            )
        })?;
    let stats = Arc::new(Mutex::new(Stats::default()));
    let mut linker = Linker::new(&engine);
    map_wasmtime(install_source_nested_three(
        &mut linker,
        Arc::clone(&stats),
        mode,
    ))?;
    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
            stats: Arc::clone(&stats),
        },
    );
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let probe = instance
        .get_export_index(&mut store, None, PROBE_NESTED_THREE_INSTANCE)
        .context("missing three-level nested-resource record stream probe export")?;
    let run = instance
        .get_export_index(&mut store, Some(&probe), "run")
        .context("missing three-level nested-resource record stream probe.run export")?;
    let run = map_wasmtime(
        instance.get_typed_func::<(), (std::result::Result<(), ErrorCode>,)>(&mut store, &run),
    )?;
    let call = map_wasmtime(
        store
            .run_concurrent(async |accessor| run.call_concurrent(&accessor, ()).await)
            .await,
    )?;
    let result = map_wasmtime(call)?;
    let expected_result = if mode == CompletionMode::Error {
        Err(ErrorCode::Io)
    } else {
        Ok(())
    };
    if result.0 != expected_result {
        bail!(
            "unexpected three-level nested-resource result: {:?}",
            result.0
        );
    }
    let snapshot = stats
        .lock()
        .expect("three-level nested record resource stats mutex poisoned");
    let expected_polls = if mode == CompletionMode::Pending {
        2
    } else {
        1
    };
    if snapshot.entries != [111, 222]
        || snapshot.stream_read_calls != 3
        || !snapshot.eof
        || snapshot.completion_polls != expected_polls
        || snapshot.pending_wakes != u32::from(mode == CompletionMode::Pending)
        || snapshot.stream_drops != 1
        || snapshot.future_drops != 1
        || snapshot.resource_created != 2
        || snapshot.resource_drops != 2
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected three-level nested-resource stats: entries={:?} reads={} eof={} completion-polls={} pending-wakes={} stream-drops={} future-drops={} resource-created={} resource-drops={} table-empty={}",
            snapshot.entries,
            snapshot.stream_read_calls,
            snapshot.eof,
            snapshot.completion_polls,
            snapshot.pending_wakes,
            snapshot.stream_drops,
            snapshot.future_drops,
            snapshot.resource_created,
            snapshot.resource_drops,
            store.data().table.is_empty(),
        );
    }
    println!(
        "Rust generic three-level nested-resource record-stream {} passed entries=[111,222] eof=true stream-reads=3 completion-polls={} pending-wakes={} resource-created=2 resource-drops=2 stream-drops=1 future-drops=1 table-empty=true result={}",
        match mode {
            CompletionMode::Pending => "pending",
            CompletionMode::Ready => "ready",
            CompletionMode::Error => "error",
        },
        snapshot.completion_polls,
        snapshot.pending_wakes,
        if mode == CompletionMode::Error {
            "Err(io)"
        } else {
            "Ok"
        },
    );
    Ok(())
}

async fn run_nested_four(component_path: &Path, mode: CompletionMode) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_component_model_async(true);
    config.wasm_component_model_more_async_builtins(true);
    config.concurrency_support(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component =
        map_wasmtime(Component::from_file(&engine, component_path)).with_context(|| {
            format!(
                "load four-level nested-resource component {}",
                component_path.display()
            )
        })?;
    let stats = Arc::new(Mutex::new(Stats::default()));
    let mut linker = Linker::new(&engine);
    map_wasmtime(install_source_nested_four(
        &mut linker,
        Arc::clone(&stats),
        mode,
    ))?;
    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
            stats: Arc::clone(&stats),
        },
    );
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let probe = instance
        .get_export_index(&mut store, None, PROBE_NESTED_FOUR_INSTANCE)
        .context("missing four-level nested-resource record stream probe export")?;
    let run = instance
        .get_export_index(&mut store, Some(&probe), "run")
        .context("missing four-level nested-resource record stream probe.run export")?;
    let run = map_wasmtime(
        instance.get_typed_func::<(), (std::result::Result<(), ErrorCode>,)>(&mut store, &run),
    )?;
    let call = map_wasmtime(
        store
            .run_concurrent(async |accessor| run.call_concurrent(&accessor, ()).await)
            .await,
    )?;
    let result = map_wasmtime(call)?;
    let expected_result = if mode == CompletionMode::Error {
        Err(ErrorCode::Io)
    } else {
        Ok(())
    };
    if result.0 != expected_result {
        bail!(
            "unexpected four-level nested-resource result: {:?}",
            result.0
        );
    }
    let snapshot = stats
        .lock()
        .expect("four-level nested record resource stats mutex poisoned");
    let expected_polls = if mode == CompletionMode::Pending {
        2
    } else {
        1
    };
    if snapshot.entries != [111, 222]
        || snapshot.stream_read_calls != 3
        || !snapshot.eof
        || snapshot.completion_polls != expected_polls
        || snapshot.pending_wakes != u32::from(mode == CompletionMode::Pending)
        || snapshot.stream_drops != 1
        || snapshot.future_drops != 1
        || snapshot.resource_created != 2
        || snapshot.resource_drops != 2
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected four-level nested-resource stats: entries={:?} reads={} eof={} completion-polls={} pending-wakes={} stream-drops={} future-drops={} resource-created={} resource-drops={} table-empty={}",
            snapshot.entries,
            snapshot.stream_read_calls,
            snapshot.eof,
            snapshot.completion_polls,
            snapshot.pending_wakes,
            snapshot.stream_drops,
            snapshot.future_drops,
            snapshot.resource_created,
            snapshot.resource_drops,
            store.data().table.is_empty(),
        );
    }
    println!(
        "Rust generic four-level nested-resource record-stream {} passed entries=[111,222] eof=true stream-reads=3 completion-polls={} pending-wakes={} resource-created=2 resource-drops=2 stream-drops=1 future-drops=1 table-empty=true result={}",
        match mode {
            CompletionMode::Pending => "pending",
            CompletionMode::Ready => "ready",
            CompletionMode::Error => "error",
        },
        snapshot.completion_polls,
        snapshot.pending_wakes,
        if mode == CompletionMode::Error {
            "Err(io)"
        } else {
            "Ok"
        },
    );
    Ok(())
}

async fn run_nested_five(component_path: &Path, mode: CompletionMode) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_component_model_async(true);
    config.wasm_component_model_more_async_builtins(true);
    config.concurrency_support(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component =
        map_wasmtime(Component::from_file(&engine, component_path)).with_context(|| {
            format!(
                "load five-level nested-resource component {}",
                component_path.display()
            )
        })?;
    let stats = Arc::new(Mutex::new(Stats::default()));
    let mut linker = Linker::new(&engine);
    map_wasmtime(install_source_nested_five(
        &mut linker,
        Arc::clone(&stats),
        mode,
    ))?;
    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
            stats: Arc::clone(&stats),
        },
    );
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let probe = instance
        .get_export_index(&mut store, None, PROBE_NESTED_FIVE_INSTANCE)
        .context("missing five-level nested-resource record stream probe export")?;
    let run = instance
        .get_export_index(&mut store, Some(&probe), "run")
        .context("missing five-level nested-resource record stream probe.run export")?;
    let run = map_wasmtime(
        instance.get_typed_func::<(), (std::result::Result<(), ErrorCode>,)>(&mut store, &run),
    )?;
    let call = map_wasmtime(
        store
            .run_concurrent(async |accessor| run.call_concurrent(&accessor, ()).await)
            .await,
    )?;
    let result = map_wasmtime(call)?;
    let expected_result = if mode == CompletionMode::Error {
        Err(ErrorCode::Io)
    } else {
        Ok(())
    };
    if result.0 != expected_result {
        bail!(
            "unexpected five-level nested-resource result: {:?}",
            result.0
        );
    }
    let snapshot = stats
        .lock()
        .expect("five-level nested record resource stats mutex poisoned");
    let expected_polls = if mode == CompletionMode::Pending {
        2
    } else {
        1
    };
    if snapshot.entries != [111, 222]
        || snapshot.stream_read_calls != 3
        || !snapshot.eof
        || snapshot.completion_polls != expected_polls
        || snapshot.pending_wakes != u32::from(mode == CompletionMode::Pending)
        || snapshot.stream_drops != 1
        || snapshot.future_drops != 1
        || snapshot.resource_created != 2
        || snapshot.resource_drops != 2
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected five-level nested-resource stats: entries={:?} reads={} eof={} completion-polls={} pending-wakes={} stream-drops={} future-drops={} resource-created={} resource-drops={} table-empty={}",
            snapshot.entries,
            snapshot.stream_read_calls,
            snapshot.eof,
            snapshot.completion_polls,
            snapshot.pending_wakes,
            snapshot.stream_drops,
            snapshot.future_drops,
            snapshot.resource_created,
            snapshot.resource_drops,
            store.data().table.is_empty(),
        );
    }
    println!(
        "Rust generic five-level nested-resource record-stream {} passed entries=[111,222] eof=true stream-reads=3 completion-polls={} pending-wakes={} resource-created=2 resource-drops=2 stream-drops=1 future-drops=1 table-empty=true result={}",
        match mode {
            CompletionMode::Pending => "pending",
            CompletionMode::Ready => "ready",
            CompletionMode::Error => "error",
        },
        snapshot.completion_polls,
        snapshot.pending_wakes,
        if mode == CompletionMode::Error {
            "Err(io)"
        } else {
            "Ok"
        },
    );
    Ok(())
}

async fn run_nested_six(component_path: &Path, mode: CompletionMode) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_component_model_async(true);
    config.wasm_component_model_more_async_builtins(true);
    config.concurrency_support(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component =
        map_wasmtime(Component::from_file(&engine, component_path)).with_context(|| {
            format!(
                "load six-level nested-resource component {}",
                component_path.display()
            )
        })?;
    let stats = Arc::new(Mutex::new(Stats::default()));
    let mut linker = Linker::new(&engine);
    map_wasmtime(install_source_nested_six(
        &mut linker,
        Arc::clone(&stats),
        mode,
    ))?;
    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
            stats: Arc::clone(&stats),
        },
    );
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let probe = instance
        .get_export_index(&mut store, None, PROBE_NESTED_SIX_INSTANCE)
        .context("missing six-level nested-resource record stream probe export")?;
    let run = instance
        .get_export_index(&mut store, Some(&probe), "run")
        .context("missing six-level nested-resource record stream probe.run export")?;
    let run = map_wasmtime(
        instance.get_typed_func::<(), (std::result::Result<(), ErrorCode>,)>(&mut store, &run),
    )?;
    let call = map_wasmtime(
        store
            .run_concurrent(async |accessor| run.call_concurrent(&accessor, ()).await)
            .await,
    )?;
    let result = map_wasmtime(call)?;
    let expected_result = if mode == CompletionMode::Error {
        Err(ErrorCode::Io)
    } else {
        Ok(())
    };
    if result.0 != expected_result {
        bail!(
            "unexpected six-level nested-resource result: {:?}",
            result.0
        );
    }
    let snapshot = stats
        .lock()
        .expect("six-level nested record resource stats mutex poisoned");
    let expected_polls = if mode == CompletionMode::Pending {
        2
    } else {
        1
    };
    if snapshot.entries != [111, 222]
        || snapshot.stream_read_calls != 3
        || !snapshot.eof
        || snapshot.completion_polls != expected_polls
        || snapshot.pending_wakes != u32::from(mode == CompletionMode::Pending)
        || snapshot.stream_drops != 1
        || snapshot.future_drops != 1
        || snapshot.resource_created != 2
        || snapshot.resource_drops != 2
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected six-level nested-resource stats: entries={:?} reads={} eof={} completion-polls={} pending-wakes={} stream-drops={} future-drops={} resource-created={} resource-drops={} table-empty={}",
            snapshot.entries,
            snapshot.stream_read_calls,
            snapshot.eof,
            snapshot.completion_polls,
            snapshot.pending_wakes,
            snapshot.stream_drops,
            snapshot.future_drops,
            snapshot.resource_created,
            snapshot.resource_drops,
            store.data().table.is_empty(),
        );
    }
    println!(
        "Rust generic six-level nested-resource record-stream {} passed entries=[111,222] eof=true stream-reads=3 completion-polls={} pending-wakes={} resource-created=2 resource-drops=2 stream-drops=1 future-drops=1 table-empty=true result={}",
        match mode {
            CompletionMode::Pending => "pending",
            CompletionMode::Ready => "ready",
            CompletionMode::Error => "error",
        },
        snapshot.completion_polls,
        snapshot.pending_wakes,
        if mode == CompletionMode::Error {
            "Err(io)"
        } else {
            "Ok"
        },
    );
    Ok(())
}

async fn run_multiple_nested(component_path: &Path, mode: CompletionMode) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_component_model_async(true);
    config.wasm_component_model_more_async_builtins(true);
    config.concurrency_support(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component =
        map_wasmtime(Component::from_file(&engine, component_path)).with_context(|| {
            format!(
                "load multiple-nested-resource component {}",
                component_path.display()
            )
        })?;
    let stats = Arc::new(Mutex::new(Stats::default()));
    let mut linker = Linker::new(&engine);
    map_wasmtime(install_source_multiple_nested(
        &mut linker,
        Arc::clone(&stats),
        mode,
    ))?;
    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
            stats: Arc::clone(&stats),
        },
    );
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let probe = instance
        .get_export_index(&mut store, None, PROBE_MULTIPLE_NESTED_INSTANCE)
        .context("missing multiple-nested-resource record stream probe export")?;
    let run = instance
        .get_export_index(&mut store, Some(&probe), "run")
        .context("missing multiple-nested-resource record stream probe.run export")?;
    let run = map_wasmtime(
        instance.get_typed_func::<(), (std::result::Result<(), ErrorCode>,)>(&mut store, &run),
    )?;
    let call = map_wasmtime(
        store
            .run_concurrent(async |accessor| run.call_concurrent(&accessor, ()).await)
            .await,
    )?;
    let result = map_wasmtime(call)?;
    let expected_result = if mode == CompletionMode::Error {
        Err(ErrorCode::Io)
    } else {
        Ok(())
    };
    if result.0 != expected_result {
        bail!("unexpected multiple-nested-resource result: {:?}", result.0);
    }
    let snapshot = stats
        .lock()
        .expect("multiple-nested record resource stats mutex poisoned");
    let expected_polls = if mode == CompletionMode::Pending {
        2
    } else {
        1
    };
    if snapshot.multi_entries != [(1, 111, 222), (2, 333, 444)]
        || snapshot.stream_read_calls != 3
        || !snapshot.eof
        || snapshot.completion_polls != expected_polls
        || snapshot.pending_wakes != u32::from(mode == CompletionMode::Pending)
        || snapshot.stream_drops != 1
        || snapshot.future_drops != 1
        || snapshot.resource_created != 4
        || snapshot.resource_drops != 4
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected multiple-nested-resource stats: entries={:?} reads={} eof={} completion-polls={} pending-wakes={} stream-drops={} future-drops={} resource-created={} resource-drops={} table-empty={}",
            snapshot.multi_entries,
            snapshot.stream_read_calls,
            snapshot.eof,
            snapshot.completion_polls,
            snapshot.pending_wakes,
            snapshot.stream_drops,
            snapshot.future_drops,
            snapshot.resource_created,
            snapshot.resource_drops,
            store.data().table.is_empty(),
        );
    }
    println!(
        "Rust generic multiple-nested-resource record-stream {} passed entries=[(1,111,222),(2,333,444)] eof=true stream-reads=3 completion-polls={} pending-wakes={} resource-created=4 resource-drops=4 stream-drops=1 future-drops=1 table-empty=true result={}",
        match mode {
            CompletionMode::Pending => "pending",
            CompletionMode::Ready => "ready",
            CompletionMode::Error => "error",
        },
        snapshot.completion_polls,
        snapshot.pending_wakes,
        if mode == CompletionMode::Error {
            "Err(io)"
        } else {
            "Ok"
        },
    );
    Ok(())
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-record-resource-stream-host-runner <component.wasm>")?;
    let mode = match std::env::var("DO_RECORD_RESOURCE_STREAM_COMPLETION").as_deref() {
        Ok("ready") => CompletionMode::Ready,
        Ok("error") => CompletionMode::Error,
        Ok("pending") | Err(_) => CompletionMode::Pending,
        Ok(other) => bail!(
            "DO_RECORD_RESOURCE_STREAM_COMPLETION must be pending, ready, or error (got {other})"
        ),
    };
    if std::env::var("DO_RECORD_RESOURCE_STREAM_VARIANT").as_deref() == Ok("multi") {
        futures::executor::block_on(run_multi(Path::new(&component_path), mode))
    } else if std::env::var("DO_RECORD_RESOURCE_STREAM_VARIANT").as_deref() == Ok("nested") {
        futures::executor::block_on(run_nested(Path::new(&component_path), mode))
    } else if std::env::var("DO_RECORD_RESOURCE_STREAM_VARIANT").as_deref() == Ok("nested-two") {
        futures::executor::block_on(run_nested_two(Path::new(&component_path), mode))
    } else if std::env::var("DO_RECORD_RESOURCE_STREAM_VARIANT").as_deref() == Ok("nested-three") {
        futures::executor::block_on(run_nested_three(Path::new(&component_path), mode))
    } else if std::env::var("DO_RECORD_RESOURCE_STREAM_VARIANT").as_deref() == Ok("nested-four") {
        futures::executor::block_on(run_nested_four(Path::new(&component_path), mode))
    } else if std::env::var("DO_RECORD_RESOURCE_STREAM_VARIANT").as_deref() == Ok("nested-five") {
        futures::executor::block_on(run_nested_five(Path::new(&component_path), mode))
    } else if std::env::var("DO_RECORD_RESOURCE_STREAM_VARIANT").as_deref() == Ok("nested-six") {
        futures::executor::block_on(run_nested_six(Path::new(&component_path), mode))
    } else if std::env::var("DO_RECORD_RESOURCE_STREAM_VARIANT").as_deref() == Ok("multiple-nested")
    {
        futures::executor::block_on(run_multiple_nested(Path::new(&component_path), mode))
    } else {
        futures::executor::block_on(run(Path::new(&component_path), mode))
    }
}
