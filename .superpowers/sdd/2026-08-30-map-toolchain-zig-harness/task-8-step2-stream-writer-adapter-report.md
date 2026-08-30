# Task 8 Step 2 stream-writer guest-producer adapter report

Date: 2026-08-31

## Changes

- Updated only the fourteen brief-listed stream-writer guest-producer shell gates.
- Each gate defines toolchain_bin="$repo_root/bin/do-toolchain" and exports DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json".
- Replaced direct wasm-tools parse/embed/new/validate calls with parse-core, embed-component, new-component, and validate-component.

## Verification

### Syntax

bash -n examples/p3-runtime/test_do_stream_writer_guest_producer_branch_terminal.sh — PASS
bash -n examples/p3-runtime/test_do_stream_writer_guest_producer_descriptor.sh — PASS
bash -n examples/p3-runtime/test_do_stream_writer_guest_producer_helper_descriptor.sh — PASS
bash -n examples/p3-runtime/test_do_stream_writer_guest_producer_helper_owned_descriptor.sh — PASS
bash -n examples/p3-runtime/test_do_stream_writer_guest_producer_helper_two_hop_descriptor.sh — PASS
bash -n examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized.sh — PASS
bash -n examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_five_hop.sh — PASS
bash -n examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_forwarding_helper.sh — PASS
bash -n examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_four_hop.sh — PASS
bash -n examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_helper.sh — PASS
bash -n examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_reordered_helper.sh — PASS
bash -n examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_six_hop.sh — PASS
bash -n examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_three_hop.sh — PASS
bash -n examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_two_hop.sh — PASS

Result: 14/14 passed.

### Repository-root execution

bash examples/p3-runtime/test_do_stream_writer_guest_producer_branch_terminal.sh — PASS
bash examples/p3-runtime/test_do_stream_writer_guest_producer_descriptor.sh — PASS
bash examples/p3-runtime/test_do_stream_writer_guest_producer_helper_descriptor.sh — FAIL (exit 1: WIT snapshot differs before adapter assembly)
bash examples/p3-runtime/test_do_stream_writer_guest_producer_helper_owned_descriptor.sh — FAIL (exit 1: current compiler UnsupportedP3AsyncComponent before adapter assembly)
bash examples/p3-runtime/test_do_stream_writer_guest_producer_helper_two_hop_descriptor.sh — FAIL (exit 1: current compiler UnsupportedP3AsyncComponent before adapter assembly)
bash examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized.sh — PASS
bash examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_five_hop.sh — PASS
bash examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_forwarding_helper.sh — PASS
bash examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_four_hop.sh — PASS
bash examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_helper.sh — PASS
bash examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_reordered_helper.sh — PASS
bash examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_six_hop.sh — PASS
bash examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_three_hop.sh — PASS
bash examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_two_hop.sh — PASS

Result: 11/14 passed; the three failures are pre-adapter Do compile/snapshot gates.

### Unrelated temporary cwd execution

cd /tmp/do-task8-step2-unrelated-fixed && bash /home/_/._/_/do/examples/p3-runtime/test_do_stream_writer_guest_producer_branch_terminal.sh — PASS
cd /tmp/do-task8-step2-unrelated-fixed && bash /home/_/._/_/do/examples/p3-runtime/test_do_stream_writer_guest_producer_descriptor.sh — PASS
cd /tmp/do-task8-step2-unrelated-fixed && bash /home/_/._/_/do/examples/p3-runtime/test_do_stream_writer_guest_producer_helper_descriptor.sh — FAIL (exit 1: WIT snapshot differs before adapter assembly)
cd /tmp/do-task8-step2-unrelated-fixed && bash /home/_/._/_/do/examples/p3-runtime/test_do_stream_writer_guest_producer_helper_owned_descriptor.sh — FAIL (exit 1: current compiler UnsupportedP3AsyncComponent before adapter assembly)
cd /tmp/do-task8-step2-unrelated-fixed && bash /home/_/._/_/do/examples/p3-runtime/test_do_stream_writer_guest_producer_helper_two_hop_descriptor.sh — FAIL (exit 1: current compiler UnsupportedP3AsyncComponent before adapter assembly)
cd /tmp/do-task8-step2-unrelated-fixed && bash /home/_/._/_/do/examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized.sh — PASS
cd /tmp/do-task8-step2-unrelated-fixed && bash /home/_/._/_/do/examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_five_hop.sh — PASS
cd /tmp/do-task8-step2-unrelated-fixed && bash /home/_/._/_/do/examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_forwarding_helper.sh — PASS
cd /tmp/do-task8-step2-unrelated-fixed && bash /home/_/._/_/do/examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_four_hop.sh — PASS
cd /tmp/do-task8-step2-unrelated-fixed && bash /home/_/._/_/do/examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_helper.sh — PASS
cd /tmp/do-task8-step2-unrelated-fixed && bash /home/_/._/_/do/examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_reordered_helper.sh — PASS
cd /tmp/do-task8-step2-unrelated-fixed && bash /home/_/._/_/do/examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_six_hop.sh — PASS
cd /tmp/do-task8-step2-unrelated-fixed && bash /home/_/._/_/do/examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_three_hop.sh — PASS
cd /tmp/do-task8-step2-unrelated-fixed && bash /home/_/._/_/do/examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_two_hop.sh — PASS

Result: 11/14 passed; same three pre-adapter failures as repository-root execution.

### Current-only guard

bash examples/p3-runtime/test_wasm_tools_current_only.sh — PASS (wasm-tools current-only guard passed through do-toolchain adapter)

### Diff check

git diff --check — PASS

## Concerns

- test_do_stream_writer_guest_producer_helper_descriptor.sh fails its existing WIT snapshot comparison before adapter operations.
- test_do_stream_writer_guest_producer_helper_owned_descriptor.sh and test_do_stream_writer_guest_producer_helper_two_hop_descriptor.sh fail existing current compiler support checks before adapter operations.
- This report does not claim Task 8 Step 2 or all pure gates complete.
