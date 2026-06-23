(* test_tokenbucket.sml -- token-bucket burst, throttle, refill, and
   steady-state throughput.

   Model under test: a bucket of `capacity` tokens that starts full and refills
   continuously at `refillPerTick` tokens per elapsed tick, capped at capacity.
   A request of `cost` tokens is allowed iff at least `cost` whole tokens are
   available after refilling to `now`, in which case `cost` are removed;
   otherwise it is rejected and nothing is consumed. `now` is a caller-supplied
   tick -- the library never reads a clock. *)

structure TokenBucketTests =
struct
  open Support
  structure R = RateLimit

  fun run () =
    let
      val () = Harness.section "token bucket: construction guards"
      val () = Harness.checkRaises "capacity <= 0 raises"
                 (fn () => R.tokenBucket { capacity = 0, refillPerTick = 1.0 })
      val () = Harness.checkRaises "negative refill raises"
                 (fn () => R.tokenBucket { capacity = 5, refillPerTick = ~1.0 })

      val () = Harness.section "token bucket: starts full, burst up to capacity"
      val tb = R.tokenBucket { capacity = 5, refillPerTick = 1.0 }
      val () = Harness.checkInt "available at start = capacity"
                 (5, R.available tb 0)
      (* Five unit requests at the same tick: all allowed (burst = capacity). *)
      val (allowed, tb1) = burst tb 0 5
      val () = Harness.checkInt "burst of 5 all allowed" (5, allowed)
      val () = Harness.checkInt "bucket empty after burst" (0, R.available tb1 0)

      val () = Harness.section "token bucket: throttled once empty"
      (* A sixth request at the same tick (no time elapsed) is rejected. *)
      val (ok6, tb2) = step tb1 0
      val () = Harness.checkBool "6th request at same tick rejected" (false, ok6)
      (* Rejected request consumes nothing: still empty. *)
      val () = Harness.checkInt "still empty after rejection" (0, R.available tb2 0)

      val () = Harness.section "token bucket: refill restores capacity"
      (* After 3 ticks at 1 token/tick, 3 tokens are back. *)
      val () = Harness.checkInt "3 tokens after 3 ticks" (3, R.available tb2 3)
      val (okA, tb3) = request tb2 3 3
      val () = Harness.checkBool "cost-3 request allowed after refill" (true, okA)
      val () = Harness.checkInt "empty again after spending 3" (0, R.available tb3 3)

      val () = Harness.section "token bucket: refill caps at capacity"
      (* Idle for a long time; tokens never exceed capacity. *)
      val () = Harness.checkInt "refill clamps to capacity"
                 (5, R.available tb3 1000)
      val tbFull = R.tokenBucket { capacity = 5, refillPerTick = 1.0 }
      val () = Harness.checkInt "full bucket idle stays at capacity"
                 (5, R.available tbFull 1000)

      val () = Harness.section "token bucket: cost larger than capacity never allowed"
      val (okBig, _) = request tbFull 0 6
      val () = Harness.checkBool "cost > capacity rejected" (false, okBig)

      val () = Harness.section "token bucket: non-positive cost is free"
      val (okZero, tbZ) = request tbFull 0 0
      val () = Harness.checkBool "zero-cost request allowed" (true, okZero)
      val () = Harness.checkInt "zero-cost consumes nothing" (5, R.available tbZ 0)

      val () = Harness.section "token bucket: fractional refill rate"
      (* 0.5 tokens/tick: empty bucket needs 2 ticks per token. *)
      val tf0 = R.tokenBucket { capacity = 4, refillPerTick = 0.5 }
      val (_, tf1) = burst tf0 0 4           (* drain to empty *)
      val () = Harness.checkInt "empty after draining" (0, R.available tf1 0)
      val () = Harness.checkInt "0 tokens after 1 tick @0.5" (0, R.available tf1 1)
      val () = Harness.checkInt "1 token after 2 ticks @0.5" (1, R.available tf1 2)
      val () = Harness.checkInt "2 tokens after 4 ticks @0.5" (2, R.available tf1 4)

      val () = Harness.section "token bucket: steady-state throughput matches refill rate"
      (* Empty bucket, then one unit request per tick for many ticks. With
         capacity 1 and refill 0.25/tick, long-run acceptance approaches the
         refill rate (~0.25 of requests). Compare the real rate with tolerance,
         never a stringified real. *)
      val ss0 = R.tokenBucket { capacity = 1, refillPerTick = 0.25 }
      val (_, ssEmpty) = step ss0 0          (* spend the initial token *)
      val nTicks = 4000
      val (acceptedSS, _) = overTicks ssEmpty (1, nTicks)
      val rate = Real.fromInt acceptedSS / Real.fromInt nTicks
      val () = checkApproxTol 0.02 "throughput approx refill rate 0.25"
                 (0.25, rate)
    in
      ()
    end
end
