(* demo.sml

   A tour of `sml-ratelimit`: drives each of the three pure rate limiters
   through a fixed sequence of caller-supplied ticks and prints the verdicts.
   Time is always an input -- the demo simply names a list of ticks; the
   library never reads a clock. The output is fully deterministic and
   byte-identical across MLton and Poly/ML -- no clocks, no randomness.

   Build and run with `make example`. *)

structure R = RateLimit

fun line s = print (s ^ "\n")
fun yn b = if b then "ALLOW " else "deny  "
fun pad3 n = StringCvt.padLeft #" " 3 (Int.toString n)

(* Drive a limiter through (now, cost) requests, printing one row each and
   threading the successor limiter. Returns the final limiter. *)
fun drive (label, lim0, reqs) =
  let
    fun go (lim, []) = lim
      | go (lim, (now, cost) :: rest) =
          let
            val avail = R.available lim now
            val (ok, lim') = R.allow lim { now = now, cost = cost }
          in
            line ("  t=" ^ pad3 now ^ "  cost=" ^ pad3 cost
                  ^ "  avail(before)=" ^ pad3 avail
                  ^ "  -> " ^ yn ok
                  ^ "  avail(after)=" ^ pad3 (R.available lim' now));
            go (lim', rest)
          end
  in
    line label; go (lim0, reqs)
  end

val () = line "=== sml-ratelimit demo ========================================"
val () = line ""
val () = line "Time is an INPUT: every row's tick `t` is supplied by the caller."
val () = line ""

(* Token bucket: capacity 5, refill 1 token/tick. Starts full, so a burst of
   five unit requests at t=0 all pass; the sixth is throttled until a refill. *)
val () = line "Token bucket  {capacity=5, refillPerTick=1.0}  (starts full)"
val _ =
  drive
    ("  burst of 6 at t=0, then wait and retry:",
     R.tokenBucket { capacity = 5, refillPerTick = 1.0 },
     [ (0,1),(0,1),(0,1),(0,1),(0,1),(0,1),  (* 5 allowed, 6th throttled *)
       (2,1),                                 (* 2 ticks -> 2 tokens back *)
       (2,1),                                 (* spend the second one     *)
       (2,1) ])                               (* empty again -> throttled  *)
val () = line ""

(* Leaky bucket: capacity 3, leak 1 unit/tick. Starts empty; admits a burst up
   to capacity, then drips one unit of headroom back per tick. *)
val () = line "Leaky bucket  {capacity=3, leakPerTick=1.0}  (starts empty)"
val _ =
  drive
    ("  fill then drain:",
     R.leakyBucket { capacity = 3, leakPerTick = 1.0 },
     [ (0,1),(0,1),(0,1),(0,1),  (* 3 admitted, 4th overflows *)
       (1,1),                     (* 1 tick -> 1 unit leaked, room for 1 *)
       (1,1) ])                   (* now full again -> rejected          *)
val () = line ""

(* Sliding window: 3 requests per 10-tick window. The weighted approximation
   frees capacity gradually as the window slides. *)
val () = line "Sliding window  {limit=3, windowTicks=10}  (weighted counter)"
val _ =
  drive
    ("  saturate window [0,10), then probe as it slides:",
     R.slidingWindow { limit = 3, windowTicks = 10 },
     [ (0,1),(0,1),(0,1),(0,1),  (* 3 allowed, 4th over the limit *)
       (10,1),                    (* edge: previous window fully weighted *)
       (15,1),                    (* half-slid: one slot freed            *)
       (19,1),                    (* nearly slid: another slot freed      *)
       (20,1) ])                  (* next window edge: prev still weighted *)
val () = line ""
val () = line "==============================================================="
