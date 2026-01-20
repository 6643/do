// Memory Allocator in do
// Memory Layout:
// Offset 0: Current heap head (Bump pointer)
// Offset 4: Current heap max (Top of allocated pages)

init() {
    // Start heap at 4096 to leave room for system use
    i32_store(0, 4096);
    i32_store(4, mem_size() * 65536);
}

malloc(size i32) -> i32 {
    ptr = i32_load(0);
    
    // 8-byte alignment: (ptr + 7) & ~7
    // Using bitwise arithmetic: (ptr + 7) / 8 * 8
    aligned_ptr = (ptr + 7) / 8 * 8;
    new_ptr = aligned_ptr + size;
    
    max = i32_load(4);
    if (new_ptr > max) {
        // Need to grow memory
        needed_pages = (new_ptr - max + 65535) / 65536;
        mem_grow(needed_pages);
        i32_store(4, mem_size() * 65536);
    }
    
    i32_store(0, new_ptr);
    aligned_ptr
}

free(ptr i32) {
    // Bump allocator doesn't support individual free.
    // In Stage 4, we will implement a Slab or Buddy allocator.
    0
}
