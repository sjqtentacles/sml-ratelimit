(* support.sml -- shared helpers for the sml-ratelimit tests.

   Rate-limiter verdicts are exact `bool`s, so the bulk of the suite uses the
   harness's `checkBool` / structural helpers directly. The few real-valued
   facts (steady-state throughput rates) are compared through an explicit
   epsilon rather than any stringification: `Real.toString` differs between
   MLton and Poly/ML, so a stringified-real assertion would not be
   byte-identical across compilers. `approxTol` pins those with a caller-chosen
   tolerance.

   The driving helpers below thread the successor limiter through a sequence of
   requests, which is the entire interaction protocol, and tally how many were
   allowed. They keep the per-policy suites focused on the assertions. *)

structure Support =
struct
  structure R = RateLimit

  fun approxTol tol (a, b) = Real.abs (a - b) <= tol

  fun checkApproxTol tol name (expected, actual) =
    Harness.check name (approxTol tol (expected, actual))

  (* One request of unit cost at tick `now`. Returns (verdict, limiter'). *)
  fun step lim now = R.allow lim { now = now, cost = 1 }

  (* `request lim now cost` -- a request of arbitrary cost. *)
  fun request lim now cost = R.allow lim { now = now, cost = cost }

  (* Fire `n` unit-cost requests, all at the same tick `now`, threading the
     limiter. Returns (allowedCount, limiter'). *)
  fun burst lim now n =
    let
      fun loop (0, allowed, l) = (allowed, l)
        | loop (k, allowed, l) =
            let val (ok, l') = step l now
            in loop (k - 1, if ok then allowed + 1 else allowed, l') end
    in
      loop (n, 0, lim)
    end

  (* Fire one unit-cost request at each tick in the inclusive range
     [lo, hi], threading the limiter. Returns (allowedCount, limiter'). *)
  fun overTicks lim (lo, hi) =
    let
      fun loop (t, allowed, l) =
        if t > hi then (allowed, l)
        else
          let val (ok, l') = step l t
          in loop (t + 1, if ok then allowed + 1 else allowed, l') end
    in
      loop (lo, 0, lim)
    end

  (* The verdicts of unit requests, one per tick across [lo, hi]. *)
  fun verdicts lim (lo, hi) =
    let
      fun loop (t, acc, l) =
        if t > hi then List.rev acc
        else
          let val (ok, l') = step l t
          in loop (t + 1, ok :: acc, l') end
    in
      loop (lo, [], lim)
    end
end
