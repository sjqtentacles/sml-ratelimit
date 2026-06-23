(* test_leakybucket.sml -- leaky-bucket burst admission, throttle, drain, and
   steady-state outflow.

   Model under test: a bucket that holds up to `capacity` units of queued work
   and drains at `leakPerTick` units per elapsed tick. It starts empty. A
   request of `cost` units is admitted iff, after leaking down to `now`, the
   bucket has room for `cost` more units without exceeding `capacity`, in which
   case `cost` units are added; otherwise it is rejected and nothing is added.
   `now` is supplied by the caller -- the library never reads a clock. *)

structure LeakyBucketTests =
struct
  open Support
  structure R = RateLimit

  fun run () =
    let
      val () = Harness.section "leaky bucket: construction guards"
      val () = Harness.checkRaises "capacity <= 0 raises"
                 (fn () => R.leakyBucket { capacity = 0, leakPerTick = 1.0 })
      val () = Harness.checkRaises "negative leak raises"
                 (fn () => R.leakyBucket { capacity = 5, leakPerTick = ~1.0 })

      val () = Harness.section "leaky bucket: starts empty, burst fills to capacity"
      val lb = R.leakyBucket { capacity = 5, leakPerTick = 1.0 }
      val () = Harness.checkInt "headroom at start = capacity"
                 (5, R.available lb 0)
      (* Five unit requests at the same tick: all admitted (fills the bucket). *)
      val (allowed, lb1) = burst lb 0 5
      val () = Harness.checkInt "burst of 5 all admitted" (5, allowed)
      val () = Harness.checkInt "no headroom after burst" (0, R.available lb1 0)

      val () = Harness.section "leaky bucket: throttled once full"
      val (ok6, lb2) = step lb1 0
      val () = Harness.checkBool "6th request at same tick rejected" (false, ok6)
      val () = Harness.checkInt "still full after rejection" (0, R.available lb2 0)

      val () = Harness.section "leaky bucket: draining frees headroom"
      (* After 3 ticks at 1 unit/tick, 3 units have drained. *)
      val () = Harness.checkInt "3 headroom after 3 ticks" (3, R.available lb2 3)
      val (okA, lb3) = request lb2 3 3
      val () = Harness.checkBool "cost-3 request admitted after drain" (true, okA)
      val () = Harness.checkInt "full again after adding 3" (0, R.available lb3 3)

      val () = Harness.section "leaky bucket: drain caps at empty"
      (* Idle for a long time: the bucket empties but never goes negative. *)
      val () = Harness.checkInt "drain clamps to empty (full headroom)"
                 (5, R.available lb3 1000)

      val () = Harness.section "leaky bucket: cost larger than capacity never admitted"
      val empty = R.leakyBucket { capacity = 5, leakPerTick = 1.0 }
      val (okBig, _) = request empty 0 6
      val () = Harness.checkBool "cost > capacity rejected" (false, okBig)

      val () = Harness.section "leaky bucket: non-positive cost is free"
      val (okZero, lz) = request empty 0 0
      val () = Harness.checkBool "zero-cost request allowed" (true, okZero)
      val () = Harness.checkInt "zero-cost adds nothing" (5, R.available lz 0)

      val () = Harness.section "leaky bucket: fractional leak rate"
      (* 0.5 units/tick: a full bucket of 4 needs 8 ticks to fully drain. *)
      val lf0 = R.leakyBucket { capacity = 4, leakPerTick = 0.5 }
      val (_, lf1) = burst lf0 0 4           (* fill to capacity *)
      val () = Harness.checkInt "full after burst" (0, R.available lf1 0)
      val () = Harness.checkInt "0 headroom after 1 tick @0.5" (0, R.available lf1 1)
      val () = Harness.checkInt "1 headroom after 2 ticks @0.5" (1, R.available lf1 2)
      val () = Harness.checkInt "2 headroom after 4 ticks @0.5" (2, R.available lf1 4)

      val () = Harness.section "leaky bucket: steady-state outflow matches leak rate"
      (* Capacity 1, leak 0.25/tick, one unit request per tick: long-run
         admission approaches the leak rate (~0.25). Tolerance, not strings. *)
      val ss0 = R.leakyBucket { capacity = 1, leakPerTick = 0.25 }
      val nTicks = 4000
      val (admittedSS, _) = overTicks ss0 (0, nTicks)
      val rate = Real.fromInt admittedSS / Real.fromInt (nTicks + 1)
      val () = checkApproxTol 0.02 "outflow approx leak rate 0.25"
                 (0.25, rate)
    in
      ()
    end
end
