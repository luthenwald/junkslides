<!-- deck v1 -->

---
<!-- slide 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e01 -->

<!-- cell 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e02 -->
# Why lenses

<!-- cell 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e03 -->
A lens is a pair of functions, _get_ and _put_,
satisfying a few round-trip laws.

<!-- notes 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e04 -->
Mention Boomerang here.

---
<!-- slide 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e05 -->

<!-- cell 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e06 -->
![A lens diagram](assets/lens.png)

---
<!-- slide 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e07 -->

<!-- cell 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e08 -->
## The laws

<!-- cell 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e09 -->
1. GetPut: put back what you got, nothing changes.
2. PutGet: get what you put.
3. PutPut: the last put wins.

<!-- cell 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e0a -->
- Lenses compose.
- They are *bidirectional* programs.

  - nested after a blank line

<!-- notes 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e0b -->
Read *Combinators for bidirectional tree transformations* again.\
Two lines, one hard break.

---
<!-- slide 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e0c -->

<!-- cell 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e0d -->
### In Gleam

<!-- cell 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e0e -->
```gleam
pub type Lens(s, a) {
  Lens(get: fn(s) -> a, put: fn(s, a) -> s)
}

pub fn compose(outer, inner) { todo }
```

<!-- cell 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e0f -->
> A lens focuses on part of a structure.

<!-- cell 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e10 -->
Call `compose` with an ![inline icon](assets/icon.png) or follow
[the paper](https://www.cis.upenn.edu/~bcpierce/papers/lenses-toplas-final.pdf).
Escapes: \_not emphasis\_ and \*not strong\*.

<!-- cell 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e11 -->

---
<!-- slide 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e12 -->

<!-- cell 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e13 -->
#### Four

##### Five

###### Six

---
<!-- slide 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e14 -->
