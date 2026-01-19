(module
  (memory (export "mem") 1)
  (func $_start (export "_start") (result i32)
    (local $tmp_ptr i32) (local $alloc_ptr i32) (local $res i32)
        local.get 2147483649 ;; Active
;; Perceus IncRC on Active
local.set 15 (local.get 2147483649)
local.get 15 (local.get 15 (i32.load offset=0) (i32.const 1) i32.add) i32.store offset=0
local.set 0
    ;; TODO: NodeTag match_expr
    local.get 2147483649 ;; Active2
;; Perceus IncRC on Active2
local.set 15 (local.get 2147483649)
local.get 15 (local.get 15 (i32.load offset=0) (i32.const 1) i32.add) i32.store offset=0
local.set 1
    ;; TODO: NodeTag match_expr
    local.get 2147483649 ;; Active2
;; Perceus IncRC on Active2
local.set 15 (local.get 2147483649)
local.get 15 (local.get 15 (i32.load offset=0) (i32.const 1) i32.add) i32.store offset=0
local.get 1 ;; a
i32.add
(if
      (then
                ;; TODO: NodeTag call
      )
    )
    ;; TODO: NodeTag match_expr
local.set 2
    ;; TODO: NodeTag call
local.set 2147483648
(if
      (then
                ;; TODO: NodeTag call
      )
    )
    i32.const 0
  )

)
