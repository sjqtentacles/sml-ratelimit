# sml-ratelimit

[![CI](https://github.com/sjqtentacles/sml-ratelimit/actions/workflows/ci.yml/badge.svg)](https://github.com/sjqtentacles/sml-ratelimit/actions/workflows/ci.yml)

Rate limiters as **pure values** in Standard ML — a token bucket, a leaky
bucket, and a weighted sliding-window counter, unified under one opaque type.
Every limiter is an immutable value; each decision returns the verdict together
with the successor limiter to thread into the next call. No FFI, no external
dependencies, and **deterministic**, byte-identically under both
[MLton](http://mlton.org/) and [Poly/ML](https://www.polyml.org/).

## Time is an input

The library **never reads a wall clock**, never calls into the OS, and never
draws randomness. Time is *always* supplied by the caller as an integer tick
`now` to each `allow` call. A fixed sequence of `(now, cost)` requests therefore
always produces the same verdicts and the same limiter states — on every run,
machine, and compiler. There is no hidden mutable state: threading the returned
limiter back in is the entire protocol.

## Status

- 59 assertions, green on MLton and Poly/ML.
- Basis library only; no vendored dependencies, builds standalone.
- Pure and deterministic across compilers: no FFI, no wall-clock, no ambient
  randomness, no threads.

## Install

With [`smlpkg`](https://github.com/diku-dk/smlpkg):

```
smlpkg add github.com/sjqtentacles/sml-ratelimit
smlpkg sync
```

Include the MLB from your own:

```
local
  $(SML_LIB)/basis/basis.mlb
  lib/github.com/sjqtentacles/sml-ratelimit/... (via smlpkg)
in
  ...
end
```

This brings `structure RateLimit` into scope.

## Quick start

```sml
structure R = RateLimit

(* Token bucket: capacity 5, refilling 1 token per tick. Starts full. *)
val tb = R.tokenBucket { capacity = 5, refillPerTick = 1.0 }

(* allow returns (verdict, successor); thread the successor forward. *)
val (ok0, tb1) = R.allow tb  { now = 0, cost = 1 }   (* true,  4 left *)
val (ok1, tb2) = R.allow tb1 { now = 0, cost = 4 }   (* true,  0 left *)
val (ok2, tb3) = R.allow tb2 { now = 0, cost = 1 }   (* false (empty) *)
val (ok3, tb4) = R.allow tb3 { now = 2, cost = 1 }   (* true  (2 refilled) *)

(* Leaky bucket: holds 3 units, draining 1 unit per tick. Starts empty. *)
val lb = R.leakyBucket { capacity = 3, leakPerTick = 1.0 }

(* Sliding window: at most 3 requests across any 10-tick window. *)
val sw = R.slidingWindow { limit = 3, windowTicks = 10 }

(* available: whole units a request could spend right now (no consumption). *)
val left = R.available tb 0    (* 5 *)
```

## API (`signature RATELIMIT`)

```sml
type t                                    (* a rate limiter (abstract) *)
type request  = { now : int, cost : int }
type decision = bool * t

(* token bucket: up to `capacity` tokens, refilling `refillPerTick`/tick.
   Starts full. Raises Domain if capacity <= 0 or refillPerTick < 0.0. *)
val tokenBucket   : { capacity : int, refillPerTick : real } -> t

(* leaky bucket: holds up to `capacity` units, draining `leakPerTick`/tick.
   Starts empty. Raises Domain if capacity <= 0 or leakPerTick < 0.0. *)
val leakyBucket   : { capacity : int, leakPerTick : real } -> t

(* sliding window: at most `limit` units of cost across any `windowTicks`
   window. Starts empty. Raises Domain if limit <= 0 or windowTicks <= 0. *)
val slidingWindow : { limit : int, windowTicks : int } -> t

(* decide a request at tick `now`; returns the verdict and the successor
   limiter to thread into the next call. A rejected request consumes nothing. *)
val allow         : t -> request -> decision

(* whole units available to a request at `now`, without consuming. >= 0. *)
val available     : t -> int -> int
```

The three policies share one opaque `t`, built by the constructor matching the
policy; a single `allow` dispatches internally. `now` is an `int` tick whose
unit is whatever the caller decides (seconds, milliseconds, frames, …); the
`refillPerTick` / `leakPerTick` rates are expressed *per tick* in those same
units, and are `real` so fractional rates are exact.

### Conventions

- **`now` is non-decreasing** across successive `allow` calls on the same
  limiter line. A `now` that is not greater than the limiter's last observed
  tick simply elapses zero ticks (no refill / no leak).
- **Non-positive `cost`** is a free request: always allowed, changes no
  accounting.
- **Rejected requests consume nothing** — the only state change on a rejection
  is advancing the observed clock to `now`.
- **Token bucket** allows a request of `cost` iff at least `cost` *whole* tokens
  are available after refilling (capped at `capacity`); permits bursts up to
  `capacity`.
- **Leaky bucket** admits `cost` iff the bucket, after draining (floored at
  empty), has room for `cost` more units without exceeding `capacity`; smooths
  bursts into a steady outflow.
- **Sliding window** uses the standard weighted previous/current fixed-window
  approximation: `estimate = prev · (windowTicks − elapsed)/windowTicks + cur`,
  where `elapsed = now mod windowTicks`. This is intentionally *more*
  conservative than a naive fixed window — under uniform traffic the long-run
  acceptance settles *below* `limit/windowTicks`, never above it — and it frees
  capacity continuously as the window slides.
- `available` is `floor`ed and clamped into `[0, capacity]` (or `[0, limit]`).

## Build & test

```
make test        # MLton
make test-poly   # Poly/ML
make all-tests   # both
make example     # build + run examples/demo.sml
make clean
```

Both compilers run the same strict-TDD suite (59 assertions) with hand-derived
expected verdicts: construction guards (`Domain` on bad parameters); burst up to
capacity then throttling; refill / drain restoring capacity over caller-supplied
ticks; fractional rates (0.5/tick) checked tick-by-tick; long-run steady-state
throughput matching the refill / leak / window rate (reals compared with an
explicit tolerance — **never** a stringified real, since `Real.toString` differs
across compilers); and the sliding window counting within the window, rejecting
beyond the limit, and freeing capacity as the window slides (weighted edge,
half-slide, and near-slide cases).

## Example

`make example` drives each limiter through a fixed sequence of caller-supplied
ticks and prints the verdicts (output is byte-identical under MLton and
Poly/ML):

```
=== sml-ratelimit demo ========================================

Time is an INPUT: every row's tick `t` is supplied by the caller.

Token bucket  {capacity=5, refillPerTick=1.0}  (starts full)
  burst of 6 at t=0, then wait and retry:
  t=  0  cost=  1  avail(before)=  5  -> ALLOW   avail(after)=  4
  t=  0  cost=  1  avail(before)=  4  -> ALLOW   avail(after)=  3
  t=  0  cost=  1  avail(before)=  3  -> ALLOW   avail(after)=  2
  t=  0  cost=  1  avail(before)=  2  -> ALLOW   avail(after)=  1
  t=  0  cost=  1  avail(before)=  1  -> ALLOW   avail(after)=  0
  t=  0  cost=  1  avail(before)=  0  -> deny    avail(after)=  0
  t=  2  cost=  1  avail(before)=  2  -> ALLOW   avail(after)=  1
  t=  2  cost=  1  avail(before)=  1  -> ALLOW   avail(after)=  0
  t=  2  cost=  1  avail(before)=  0  -> deny    avail(after)=  0

Leaky bucket  {capacity=3, leakPerTick=1.0}  (starts empty)
  fill then drain:
  t=  0  cost=  1  avail(before)=  3  -> ALLOW   avail(after)=  2
  t=  0  cost=  1  avail(before)=  2  -> ALLOW   avail(after)=  1
  t=  0  cost=  1  avail(before)=  1  -> ALLOW   avail(after)=  0
  t=  0  cost=  1  avail(before)=  0  -> deny    avail(after)=  0
  t=  1  cost=  1  avail(before)=  1  -> ALLOW   avail(after)=  0
  t=  1  cost=  1  avail(before)=  0  -> deny    avail(after)=  0

Sliding window  {limit=3, windowTicks=10}  (weighted counter)
  saturate window [0,10), then probe as it slides:
  t=  0  cost=  1  avail(before)=  3  -> ALLOW   avail(after)=  2
  t=  0  cost=  1  avail(before)=  2  -> ALLOW   avail(after)=  1
  t=  0  cost=  1  avail(before)=  1  -> ALLOW   avail(after)=  0
  t=  0  cost=  1  avail(before)=  0  -> deny    avail(after)=  0
  t= 10  cost=  1  avail(before)=  0  -> deny    avail(after)=  0
  t= 15  cost=  1  avail(before)=  1  -> ALLOW   avail(after)=  0
  t= 19  cost=  1  avail(before)=  1  -> ALLOW   avail(after)=  0
  t= 20  cost=  1  avail(before)=  1  -> ALLOW   avail(after)=  0

===============================================================
```

### Poly/ML note

CI builds Poly/ML 5.9.1 from source rather than using the Ubuntu package
(Poly/ML 5.7.1), whose X86 code generator can crash on some inputs. See
`.github/workflows/ci.yml`.

## License

MIT — see [LICENSE](LICENSE).
