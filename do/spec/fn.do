Person {
    id  i32
    age i32
}

#to_string(T) -> Text
#T{.age i32}

to_string(p Person) Text {
    => "ID: ${get(p, .id)}"
}

print_info(p T) {
    val = get(p, .age)
    print(to_string(p))
}

test "generic function with set" {
    // 实例化 Person
    p = set(Person, { 
        .id: 1, 
        .age: 30 
    })
    
    print_info(p)
}