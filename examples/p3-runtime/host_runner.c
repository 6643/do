#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <wasmtime.h>

typedef struct {
  size_t callback_calls;
  size_t continuation_polls;
  size_t active_futures;
  size_t max_active_futures;
  size_t nested_call_attempts;
  size_t call_invocations;
  size_t queue_waits;
  bool p3_wait_for;
} event_state_t;

static void print_error(const char *stage, wasmtime_error_t *error) {
  wasm_name_t message;
  wasmtime_error_message(error, &message);
  fprintf(stderr, "%s: %.*s\n", stage, (int)message.size, message.data);
  wasm_byte_vec_delete(&message);
  wasmtime_error_delete(error);
}

static bool complete_on_second_poll(void *env) {
  event_state_t *state = env;
  state->continuation_polls += 1;
  return state->continuation_polls >= 2;
}

static void next_event(void *env, wasmtime_context_t *context,
                       const wasmtime_component_func_type_t *type,
                       wasmtime_component_val_t *args, size_t nargs,
                       wasmtime_component_val_t *results, size_t nresults,
                       wasmtime_error_t **error,
                       wasmtime_async_continuation_t *continuation) {
  event_state_t *state = env;
  (void)context;

  if (state->p3_wait_for) {
    if (!wasmtime_component_func_type_async(type) || nargs != 1 ||
        nresults != 0 || args[0].kind != WASMTIME_COMPONENT_U64 ||
        args[0].of.u64 != 27815) {
      *error = wasmtime_error_new("wait-for ABI mismatch");
      return;
    }
  } else if (nargs != 0 || nresults != 1) {
    *error = wasmtime_error_new("next-event ABI mismatch");
    return;
  }

  state->callback_calls += 1;
  if (!state->p3_wait_for) {
    results[0].kind = WASMTIME_COMPONENT_U32;
    results[0].of.u32 = 27815;
  }
  continuation->callback = complete_on_second_poll;
  continuation->env = state;
  continuation->finalizer = NULL;
}

static wasmtime_call_future_t *start_component_call(
    event_state_t *state, const wasmtime_component_func_t *function,
    wasmtime_context_t *context, wasmtime_component_val_t *result,
    wasmtime_error_t **error) {
  if (state->active_futures != 0) {
    state->nested_call_attempts += 1;
    return NULL;
  }

  state->call_invocations += 1;
  wasmtime_call_future_t *future = wasmtime_component_func_call_async(
      function, context, NULL, 0, result, 1, error);
  if (future != NULL) {
    state->active_futures = 1;
    if (state->max_active_futures < state->active_futures) {
      state->max_active_futures = state->active_futures;
    }
  }
  return future;
}

static int read_file(const char *path, wasm_byte_vec_t *bytes) {
  FILE *file = fopen(path, "rb");
  long length;

  if (file == NULL) {
    perror(path);
    return 1;
  }
  if (fseek(file, 0, SEEK_END) != 0 || (length = ftell(file)) < 0 ||
      fseek(file, 0, SEEK_SET) != 0) {
    perror(path);
    fclose(file);
    return 1;
  }

  wasm_byte_vec_new_uninitialized(bytes, (size_t)length);
  if (fread(bytes->data, 1, bytes->size, file) != bytes->size) {
    perror(path);
    wasm_byte_vec_delete(bytes);
    fclose(file);
    return 1;
  }
  fclose(file);
  return 0;
}

static int write_file(const char *path, const wasm_byte_vec_t *bytes) {
  FILE *file = fopen(path, "wb");
  if (file == NULL) {
    perror(path);
    return 1;
  }
  if (fwrite(bytes->data, 1, bytes->size, file) != bytes->size) {
    perror(path);
    fclose(file);
    return 1;
  }
  fclose(file);
  return 0;
}

int main(int argc, char **argv) {
  const bool p3_wait_for = argc == 4 && strcmp(argv[3], "P3 wait-for") == 0;
  const bool host_drive_queue =
      argc == 4 && strcmp(argv[3], "C API host-drive queue") == 0;
  const char *instance_name = p3_wait_for
                                  ? "wasi:clocks/monotonic-clock@0.3.0"
                                  : "do:component-async-probe/host-events@0.1.0";
  const char *function_name = p3_wait_for ? "wait-for" : "next-event";
  const char *export_name = "run";
  wasm_config_t *config = NULL;
  wasm_engine_t *engine = NULL;
  wasmtime_store_t *store = NULL;
  wasmtime_component_t *component = NULL;
  wasmtime_component_linker_t *linker = NULL;
  wasmtime_component_linker_instance_t *root = NULL;
  wasmtime_component_linker_instance_t *host = NULL;
  wasmtime_component_export_index_t *export_index = NULL;
  wasm_byte_vec_t wat = {0};
  wasm_byte_vec_t component_bytes = {0};
  wasmtime_component_instance_t instance;
  wasmtime_component_func_t function;
  wasmtime_component_val_t p3_arg = {0};
  wasmtime_component_val_t result = {0};
  wasmtime_error_t *error = NULL;
  wasmtime_call_future_t *future = NULL;
  event_state_t state = {.p3_wait_for = p3_wait_for};
  size_t call_polls = 0;
  int status = 1;

  if (argc != 4) {
    fprintf(stderr, "usage: %s COMPONENT_WAT OUTPUT_WASM LABEL\n", argv[0]);
    return 2;
  }
  if (read_file(argv[1], &wat) != 0) {
    return 1;
  }
  if (wasmtime_wat2wasm(wat.data, wat.size, &component_bytes) != NULL) {
    fprintf(stderr, "wasmtime_wat2wasm failed\n");
    goto done;
  }
  if (write_file(argv[2], &component_bytes) != 0) {
    goto done;
  }

  config = wasm_config_new();
  wasmtime_config_wasm_component_model_set(config, true);
  wasmtime_config_wasm_component_model_async_set(config, true);
  wasmtime_config_wasm_component_model_more_async_builtins_set(config, true);
  wasmtime_config_wasm_gc_set(config, true);
  engine = wasm_engine_new_with_config(config);
  config = NULL;
  store = wasmtime_store_new(engine, NULL, NULL);

  error = wasmtime_component_new(engine, (const uint8_t *)component_bytes.data,
                                 component_bytes.size, &component);
  if (error != NULL) {
    print_error("wasmtime_component_new", error);
    error = NULL;
    goto done;
  }
  linker = wasmtime_component_linker_new(engine);
  root = wasmtime_component_linker_root(linker);
  error = wasmtime_component_linker_instance_add_instance(
      root, instance_name, strlen(instance_name), &host);
  if (error == NULL) {
    error = wasmtime_component_linker_instance_add_func_async(
        host, function_name, strlen(function_name), next_event, &state, NULL);
  }
  wasmtime_component_linker_instance_delete(host);
  host = NULL;
  wasmtime_component_linker_instance_delete(root);
  root = NULL;
  if (error != NULL) {
    print_error("component linker host-events", error);
    error = NULL;
    goto done;
  }

  future = wasmtime_component_linker_instantiate_async(
      linker, wasmtime_store_context(store), component, &instance, &error);
  while (!wasmtime_call_future_poll(future)) {
  }
  wasmtime_call_future_delete(future);
  future = NULL;
  if (error != NULL) {
    print_error("component instantiate", error);
    error = NULL;
    goto done;
  }
  export_index = wasmtime_component_instance_get_export_index(
      &instance, wasmtime_store_context(store), NULL, export_name,
      strlen(export_name));
  if (export_index == NULL || !wasmtime_component_instance_get_func(
                                  &instance, wasmtime_store_context(store),
                                  export_index, &function)) {
    fprintf(stderr, "missing component export: %s\n", export_name);
    goto done;
  }

  if (p3_wait_for) {
    p3_arg.kind = WASMTIME_COMPONENT_U64;
    p3_arg.of.u64 = 27815;
  }

  if (host_drive_queue) {
    const size_t task_count = 2;
    size_t next_task = 0;
    size_t completed_tasks = 0;

    while (completed_tasks < task_count) {
      if (future == NULL) {
        state.continuation_polls = 0;
        future = start_component_call(&state, &function,
                                      wasmtime_store_context(store), &result,
                                      &error);
        if (future == NULL) {
          if (error == NULL) {
            fprintf(stderr, "host-drive queue call returned no future\n");
          }
          goto done;
        }
        next_task += 1;
        continue;
      }

      if (next_task < task_count) {
        state.queue_waits += 1;
      }
      call_polls += 1;
      if (!wasmtime_call_future_poll(future)) {
        continue;
      }

      wasmtime_call_future_delete(future);
      future = NULL;
      state.active_futures = 0;
      completed_tasks += 1;
    }

    if (state.call_invocations != task_count || completed_tasks != task_count ||
        state.queue_waits == 0 || state.max_active_futures != 1 ||
        state.nested_call_attempts != 0 || state.callback_calls != task_count ||
        result.kind != WASMTIME_COMPONENT_U32 || result.of.u32 != 27815) {
      fprintf(stderr,
              "unexpected host-drive queue trace: tasks=%zu completed=%zu "
              "calls=%zu queue-waits=%zu active-futures-max=%zu "
              "nested-call-attempts=%zu callbacks=%zu result_kind=%u result=%u\n",
              task_count, completed_tasks, state.call_invocations,
              state.queue_waits, state.max_active_futures,
              state.nested_call_attempts, state.callback_calls,
              (unsigned)result.kind, result.of.u32);
      goto done;
    }

    printf("C API host-drive queue probe passed: tasks=%zu completed=%zu "
           "calls=%zu queued=1 active-futures-max=%zu "
           "nested-call-attempts=%zu polls=%zu\n",
           task_count, completed_tasks, state.call_invocations,
           state.max_active_futures, state.nested_call_attempts, call_polls);
    status = 0;
    goto done;
  }

  future = wasmtime_component_func_call_async(
      &function, wasmtime_store_context(store),
      p3_wait_for ? &p3_arg : NULL, p3_wait_for ? 1 : 0,
      p3_wait_for ? NULL : &result, p3_wait_for ? 0 : 1, &error);
  while (!wasmtime_call_future_poll(future)) {
    call_polls += 1;
  }
  wasmtime_call_future_delete(future);
  future = NULL;
  if (error != NULL) {
    print_error("component call", error);
    error = NULL;
    goto done;
  }
  if (state.callback_calls != 1 || state.continuation_polls < 2 ||
      call_polls < 1 || (!p3_wait_for &&
                         (result.kind != WASMTIME_COMPONENT_U32 ||
                          result.of.u32 != 27815))) {
    fprintf(stderr,
            "unexpected async trace: callbacks=%zu continuation_polls=%zu "
            "call_polls=%zu result_kind=%u result=%u\n",
            state.callback_calls, state.continuation_polls, call_polls,
            (unsigned)result.kind, result.of.u32);
    goto done;
  }

  if (p3_wait_for) {
    printf("P3 wait-for component probe passed: callbacks=%zu "
           "continuation_polls=%zu call_polls=%zu duration=%llu\n",
           state.callback_calls, state.continuation_polls, call_polls,
           (unsigned long long)p3_arg.of.u64);
  } else {
    printf("generic component %s probe passed: callbacks=%zu "
           "continuation_polls=%zu call_polls=%zu result=%u\n",
           argv[3], state.callback_calls, state.continuation_polls, call_polls,
           result.of.u32);
  }
  status = 0;

done:
  if (future != NULL) {
    wasmtime_call_future_delete(future);
  }
  if (export_index != NULL) {
    wasmtime_component_export_index_delete(export_index);
  }
  if (host != NULL) {
    wasmtime_component_linker_instance_delete(host);
  }
  if (root != NULL) {
    wasmtime_component_linker_instance_delete(root);
  }
  if (linker != NULL) {
    wasmtime_component_linker_delete(linker);
  }
  if (component != NULL) {
    wasmtime_component_delete(component);
  }
  if (store != NULL) {
    wasmtime_store_delete(store);
  }
  if (engine != NULL) {
    wasm_engine_delete(engine);
  }
  if (config != NULL) {
    wasm_config_delete(config);
  }
  wasm_byte_vec_delete(&component_bytes);
  wasm_byte_vec_delete(&wat);
  return status;
}
