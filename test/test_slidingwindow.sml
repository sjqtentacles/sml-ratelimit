(* test_slidingwindow.sml -- sliding-window counter: counting within the
   window, rejecting beyond the limit, and freeing capacity as the window
   slides.

   Model under test: the standard weighted previous/current fixed-window
   approximation. Ticks are partitioned into fixed windows of `windowTicks`.
   The limiter keeps the request count in the current window and the previous
   window; the estimated load at `now` is

       estimate = prevCount * ((windowTicks - elapsed) / windowTicks) + curCount

   where `elapsed = now mod windowTicks` is how far `now` sits into its window.
   A request of `cost` is allowed iff `estimate + cost <= limit`, in which case
   `cost` is added to the current window's count. `now` is supplied by the
   caller -- the library never reads a clock.

   The hand-checked vectors below use `limit = 3`, `windowTicks = 10`. *)

structure SlidingWindowTests =
struct
  open Support
  structure R = RateLimit

  fun run () =
    let
      val () = Harness.section "sliding window: construction guards"
      val () = Harness.checkRaises "limit <= 0 raises"
                 (fn () => R.slidingWindow { limit = 0, windowTicks = 10 })
      val () = Harness.checkRaises "windowTicks <= 0 raises"
                 (fn () => R.slidingWindow { limit = 3, windowTicks = 0 })

      val () = Harness.section "sliding window: counts within the window"
      val sw = R.slidingWindow { limit = 3, windowTicks = 10 }
      val () = Harness.checkInt "available at start = limit" (3, R.available sw 0)
      (* First window [0,10): three unit requests are allowed, the fourth not. *)
      val (ok1, sw1) = step sw 0
      val (ok2, sw2) = step sw1 1
      val (ok3, sw3) = step sw2 2
      val () = Harness.checkBool "1st in window allowed" (true, ok1)
      val () = Harness.checkBool "2nd in window allowed" (true, ok2)
      val () = Harness.checkBool "3rd in window allowed" (true, ok3)
      val () = Harness.checkInt "limit reached: 0 available" (0, R.available sw3 3)
      val (ok4, sw4) = step sw3 3
      val () = Harness.checkBool "4th within window rejected" (false, ok4)

      val () = Harness.section "sliding window: rejected request is not counted"
      (* sw4 saw the rejected 4th; the count must still be exactly 3, so once
         the window fully rolls over capacity returns to the full limit. *)
      val () = Harness.checkInt "fresh window restores full limit"
                 (3, R.available sw4 20)

      val () = Harness.section "sliding window: weight frees capacity as it slides"
      (* Fill 3 requests early in window [0,10) (all at tick 0), then probe in
         the next window [10,20). At tick `now` in the second window the
         previous count (3) is weighted by (10 - (now mod 10))/10:
            now=10 -> weight 1.0  -> estimate 3.0  -> 0 free
            now=15 -> weight 0.5  -> estimate 1.5  -> floor(3-1.5)=1 free
            now=19 -> weight 0.1  -> estimate 0.3  -> floor(3-0.3)=2 free *)
      val full = R.slidingWindow { limit = 3, windowTicks = 10 }
      val (_, full3) = burst full 0 3        (* 3 requests at tick 0 *)
      val () = Harness.checkInt "no capacity at window edge (now=10)"
                 (0, R.available full3 10)
      val () = Harness.checkInt "half-weighted prev frees 1 (now=15)"
                 (1, R.available full3 15)
      val () = Harness.checkInt "mostly-slid window frees 2 (now=19)"
                 (2, R.available full3 19)

      val () = Harness.section "sliding window: rejects beyond limit at boundary"
      (* At now=10 the estimate is exactly 3.0, so any positive cost is over. *)
      val (okEdge, _) = step full3 10
      val () = Harness.checkBool "request at saturated edge rejected"
                 (false, okEdge)
      (* At now=15 one unit fits (estimate 1.5 + 1 = 2.5 <= 3) ... *)
      val (okMid, full3b) = step full3 15
      val () = Harness.checkBool "one request fits mid-slide" (true, okMid)
      (* ... but a second one does not (estimate now ~ 1.5 + 1 + 1 = 3.5). *)
      val (okMid2, _) = step full3b 15
      val () = Harness.checkBool "second request mid-slide rejected"
                 (false, okMid2)

      val () = Harness.section "sliding window: cost larger than limit never allowed"
      val (okBig, _) = request full 0 4
      val () = Harness.checkBool "cost > limit rejected" (false, okBig)

      val () = Harness.section "sliding window: non-positive cost is free"
      val (okZero, fz) = request full 0 0
      val () = Harness.checkBool "zero-cost request allowed" (true, okZero)
      val () = Harness.checkInt "zero-cost counts nothing" (3, R.available fz 0)

      val () = Harness.section "sliding window: long-run rate is steady and bounded"
      (* limit 5 per window of 10 ticks; one request per tick over many windows.
         The weighted previous/current approximation is deliberately *more*
         conservative than the naive fixed-window rate of limit/windowTicks
         (0.5): the weighted previous count keeps the running estimate above the
         current-window count alone, so uniform traffic settles to a steady
         long-run acceptance of ~0.40 -- below the nominal 0.5 cap, never above
         it. We pin that steady ceiling with tolerance, never a stringified
         real. *)
      val ss = R.slidingWindow { limit = 5, windowTicks = 10 }
      val nTicks = 4000
      val (accepted, _) = overTicks ss (0, nTicks)
      val rate = Real.fromInt accepted / Real.fromInt (nTicks + 1)
      val () = checkApproxTol 0.02 "steady throughput approx 0.40, under the 0.5 cap"
                 (0.40, rate)
      val () = Harness.check "throughput never exceeds limit/window cap"
                 (rate <= 0.5)
    in
      ()
    end
end
