(module
  (memory 1)
  (export "memory" (memory 0))
  (export "main" (func $main))
  (func $malloc (result i32)
    (local $tmp_ptr i32) (local $rc_ptr i32) (local $tag i32)
    (local $l0_i32 i32)
    (local $l1_i32 i32)
    (local $l2_i32 i32)
    (local $l3_i32 i32)
    (local $l4_i32 i32)
    (local $l5_i32 i32)
    (local $l6_i32 i32)
    (local $l7_i32 i32)
    (local $l8_i32 i32)
    (local $l9_i32 i32)
    (local $l10_i32 i32)
    (local $l11_i32 i32)
    (local $l12_i32 i32)
    (local $l13_i32 i32)
    (local $l14_i32 i32)
    (local $l15_i32 i32)
    i32.const 0
    ;; --- RC Cleanup ---
    i32.const 0
  )
  (func $len (result i32)
    (local $tmp_ptr i32) (local $rc_ptr i32) (local $tag i32)
    (local $l0_i32 i32)
    (local $l1_i32 i32)
    (local $l2_i32 i32)
    (local $l3_i32 i32)
    (local $l4_i32 i32)
    (local $l5_i32 i32)
    (local $l6_i32 i32)
    (local $l7_i32 i32)
    (local $l8_i32 i32)
    (local $l9_i32 i32)
    (local $l10_i32 i32)
    (local $l11_i32 i32)
    (local $l12_i32 i32)
    (local $l13_i32 i32)
    (local $l14_i32 i32)
    (local $l15_i32 i32)
    local.get 0 ;; s
    local.set $tmp_ptr
    local.get $tmp_ptr i32.load offset=12
    ;; --- RC Cleanup ---
    i32.const 0
  )
  (func $test_text (result i32)
    (local $tmp_ptr i32) (local $rc_ptr i32) (local $tag i32)
    (local $l0_i32 i32)
    (local $l1_i32 i32)
    (local $l2_i32 i32)
    (local $l3_i32 i32)
    (local $l4_i32 i32)
    (local $l5_i32 i32)
    (local $l6_i32 i32)
    (local $l7_i32 i32)
    (local $l8_i32 i32)
    (local $l9_i32 i32)
    (local $l10_i32 i32)
    (local $l11_i32 i32)
    (local $l12_i32 i32)
    (local $l13_i32 i32)
    (local $l14_i32 i32)
    (local $l15_i32 i32)
    ;; Literal Text: "Hello World"
    i32.const 16 call $malloc
    local.set $tmp_ptr
    local.get $tmp_ptr i32.const 1 i32.store offset=0 ;; RC
    local.get $tmp_ptr i32.const 0 i32.store offset=4 ;; ID
    local.get $tmp_ptr
    local.set 0
    local.get 0 ;; s
    call $len
    local.set 1
    local.get 1 ;; l
    ;; --- RC Cleanup ---
    i32.const 0
  )
  (func $main (result i32)
    (local $tmp_ptr i32) (local $rc_ptr i32) (local $tag i32)
    (local $l0_i32 i32)
    (local $l1_i32 i32)
    (local $l2_i32 i32)
    (local $l3_i32 i32)
    (local $l4_i32 i32)
    (local $l5_i32 i32)
    (local $l6_i32 i32)
    (local $l7_i32 i32)
    (local $l8_i32 i32)
    (local $l9_i32 i32)
    (local $l10_i32 i32)
    (local $l11_i32 i32)
    (local $l12_i32 i32)
    (local $l13_i32 i32)
    (local $l14_i32 i32)
    (local $l15_i32 i32)
    call $test_text
    i32.const 0
  )
)
