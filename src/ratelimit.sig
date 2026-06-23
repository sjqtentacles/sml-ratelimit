(* ratelimit.sig

   Rate limiters as pure values. A limiter is an immutable `t`; every decision
   is made by `allow`, which takes the current limiter together with a
   caller-supplied integer tick `now` and a request `cost`, and returns the
   verdict together with the *successor* limiter. Threading that successor back
   in is the whole protocol: there is no hidden state and no mutation.

   Time is always an input. The library NEVER reads a wall clock, never calls
   into the OS, and never draws randomness, so a fixed sequence of
   `(now, cost)` requests always yields the same verdicts and the same limiter
   states on every run, machine, and compiler. `now` is an `int` tick whose
   unit is whatever the caller decides (seconds, milliseconds, frames, ...);
   the refill / leak rates below are expressed *per tick* in those same units.

   Three classic policies are unified under one opaque type, each built by its
   own constructor:

     - `tokenBucket {capacity, refillPerTick}` -- a bucket holding up to
       `capacity` tokens that refills continuously at `refillPerTick` tokens
       per elapsed tick. A request of `cost` tokens is allowed iff at least
       `cost` whole tokens are available after refilling to `now`; if allowed,
       `cost` tokens are removed. Permits bursts up to `capacity`.

     - `leakyBucket {capacity, leakPerTick}` -- a bucket (queue) that drains at
       `leakPerTick` units per elapsed tick. A request of `cost` is admitted
       iff the bucket, after leaking down to `now`, has room for `cost` more
       units without exceeding `capacity`; if admitted, `cost` units are added.
       Smooths bursts into a steady outflow.

     - `slidingWindow {limit, windowTicks}` -- allows at most `limit` units of
       cost across any window of `windowTicks` ending at `now`, using the
       standard weighted previous/current fixed-window approximation. Frees
       capacity continuously as the window slides forward.

   Rates (`refillPerTick`, `leakPerTick`) are reals so that fractional
   per-tick rates are exact; all comparisons inside the library are arithmetic,
   never on stringified reals. Capacities, limits, windows, `now`, and `cost`
   are `int` (MLton's default `Int` is 32-bit; values stay well within range).

   Conventions:
     - `now` should be non-decreasing across successive `allow` calls on the
       same limiter line; a `now` that is not greater than the limiter's last
       observed tick simply elapses zero ticks (no refill / no leak).
     - A non-positive `cost` is treated as a free request: it is always allowed
       and changes no accounting.
     - Constructors raise `Domain` on non-sensical parameters (non-positive
       capacity / limit / window, or a negative rate). *)

signature RATELIMIT =
sig
  (* A rate limiter. Abstract: build it with one of the constructors below and
     advance it with `allow`. *)
  type t

  (* The three policies share this verdict/decision shape. *)
  type request = { now : int, cost : int }
  type decision = bool * t

  (* Token bucket: up to `capacity` tokens, refilling at `refillPerTick` tokens
     per elapsed tick. Starts full. Raises `Domain` if `capacity <= 0` or
     `refillPerTick < 0.0`. *)
  val tokenBucket : { capacity : int, refillPerTick : real } -> t

  (* Leaky bucket: holds up to `capacity` units, draining at `leakPerTick`
     units per elapsed tick. Starts empty. Raises `Domain` if `capacity <= 0`
     or `leakPerTick < 0.0`. *)
  val leakyBucket : { capacity : int, leakPerTick : real } -> t

  (* Sliding-window counter: at most `limit` units of cost across any window of
     `windowTicks`. Starts empty. Raises `Domain` if `limit <= 0` or
     `windowTicks <= 0`. *)
  val slidingWindow : { limit : int, windowTicks : int } -> t

  (* `allow lim {now, cost}` decides whether a request of `cost` units at tick
     `now` is permitted, and returns `(verdict, lim')` where `lim'` is the
     limiter to thread into the next call. When `verdict` is `false` the
     accounting is unchanged except for advancing the observed clock to `now`,
     so a rejected request consumes nothing. *)
  val allow : t -> request -> decision

  (* The number of whole units currently available to a request at tick `now`,
     without consuming anything: tokens left in a token bucket, head-room in a
     leaky bucket, or `limit` minus the weighted count in a sliding window.
     Never negative. Useful for diagnostics and for the examples. *)
  val available : t -> int -> int
end
