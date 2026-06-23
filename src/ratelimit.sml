(* ratelimit.sml -- pure rate limiters.

   The three policies are unified under one opaque datatype `t`, with a private
   record of state per policy. `allow` dispatches on the policy, computes the
   verdict from the caller-supplied tick, and returns the successor limiter.
   Nothing here reads a clock, performs IO, draws randomness, or uses threads:
   every value is a deterministic function of its inputs, so behaviour is
   byte-identical under MLton and Poly/ML. ASCII '-' is used throughout (never
   the SML negation glyph) and no list-sorting library is needed. *)

structure RateLimit :> RATELIMIT =
struct
  type request = { now : int, cost : int }

  (* Per-policy mutable-free state. `last` is the most recent tick observed by
     this limiter line; refills and leaks are computed from `now - last`.

       TB: `capacity` whole-token ceiling, continuous `refill` rate, current
           real-valued `tokens` available.
       LB: `capacity` ceiling, continuous `leak` rate, current real-valued
           `level` (queued units).
       SW: `limit` per `window` ticks, `winStart` is the start tick of the
           current fixed window, `cur` / `prev` are the counts in the current
           and immediately-previous windows. *)
  datatype t =
      TB of { capacity : int, refill : real, tokens : real, last : int }
    | LB of { capacity : int, leak : real, level : real, last : int }
    | SW of { limit : int, window : int,
              winStart : int, cur : int, prev : int }

  type decision = bool * t

  (* Whole units, floored and clamped into [0, cap]. *)
  fun clampFloor (x, cap) =
    let
      val n = Real.floor x
    in
      if n < 0 then 0 else if n > cap then cap else n
    end

  fun tokenBucket { capacity, refillPerTick } =
    if capacity <= 0 orelse refillPerTick < 0.0 then raise Domain
    else TB { capacity = capacity, refill = refillPerTick,
              tokens = Real.fromInt capacity, last = 0 }

  fun leakyBucket { capacity, leakPerTick } =
    if capacity <= 0 orelse leakPerTick < 0.0 then raise Domain
    else LB { capacity = capacity, leak = leakPerTick,
              level = 0.0, last = 0 }

  fun slidingWindow { limit, windowTicks } =
    if limit <= 0 orelse windowTicks <= 0 then raise Domain
    else SW { limit = limit, window = windowTicks,
              winStart = 0, cur = 0, prev = 0 }

  (* Elapsed ticks since `last`, never negative (a stale `now` elapses none). *)
  fun elapsed (now, last) =
    if now > last then Real.fromInt (now - last) else 0.0

  (* --- token bucket ----------------------------------------------------- *)

  (* Tokens available after refilling to `now`, capped at capacity. *)
  fun tbRefill (capacity, refill, tokens, last, now) =
    let
      val grown = tokens + refill * elapsed (now, last)
      val cap = Real.fromInt capacity
    in
      if grown > cap then cap else grown
    end

  (* --- leaky bucket ----------------------------------------------------- *)

  (* Level after leaking to `now`, never below empty. *)
  fun lbLeak (leak, level, last, now) =
    let
      val drained = level - leak * elapsed (now, last)
    in
      if drained < 0.0 then 0.0 else drained
    end

  (* --- sliding window --------------------------------------------------- *)

  (* Roll the fixed window forward so that `now` falls inside the current
     window, carrying `cur`/`prev` appropriately, then return the rolled state
     together with the weighted estimate of the load at `now`. *)
  fun swRoll (limit, window, winStart, cur, prev, now) =
    let
      (* Index of `now`'s window relative to the stored current window. *)
      val shift =
        if now < winStart then 0
        else (now - winStart) div window
      val (winStart', cur', prev') =
        if shift <= 0 then (winStart, cur, prev)
        else if shift = 1 then (winStart + window, 0, cur)
        else (winStart + shift * window, 0, 0)
      val intoWindow = now - winStart'          (* 0 .. window-1 *)
      val weight =
        Real.fromInt (window - intoWindow) / Real.fromInt window
      val estimate = Real.fromInt prev' * weight + Real.fromInt cur'
    in
      { winStart = winStart', cur = cur', prev = prev', estimate = estimate }
    end

  (* --- allow ------------------------------------------------------------ *)

  fun allow lim { now, cost } =
    case lim of
      TB { capacity, refill, tokens, last } =>
        let
          val avail = tbRefill (capacity, refill, tokens, last, now)
        in
          if cost <= 0 then
            (true, TB { capacity = capacity, refill = refill,
                        tokens = avail, last = now })
          else if Real.fromInt cost <= avail then
            (true, TB { capacity = capacity, refill = refill,
                        tokens = avail - Real.fromInt cost, last = now })
          else
            (false, TB { capacity = capacity, refill = refill,
                         tokens = avail, last = now })
        end
    | LB { capacity, leak, level, last } =>
        let
          val lvl = lbLeak (leak, level, last, now)
          val cap = Real.fromInt capacity
        in
          if cost <= 0 then
            (true, LB { capacity = capacity, leak = leak,
                        level = lvl, last = now })
          else if lvl + Real.fromInt cost <= cap then
            (true, LB { capacity = capacity, leak = leak,
                        level = lvl + Real.fromInt cost, last = now })
          else
            (false, LB { capacity = capacity, leak = leak,
                         level = lvl, last = now })
        end
    | SW { limit, window, winStart, cur, prev } =>
        let
          val { winStart = ws, cur = c, prev = p, estimate } =
            swRoll (limit, window, winStart, cur, prev, now)
        in
          if cost <= 0 then
            (true, SW { limit = limit, window = window,
                        winStart = ws, cur = c, prev = p })
          else if estimate + Real.fromInt cost <= Real.fromInt limit then
            (true, SW { limit = limit, window = window,
                        winStart = ws, cur = c + cost, prev = p })
          else
            (false, SW { limit = limit, window = window,
                         winStart = ws, cur = c, prev = p })
        end

  (* --- available -------------------------------------------------------- *)

  fun available lim now =
    case lim of
      TB { capacity, refill, tokens, last } =>
        clampFloor (tbRefill (capacity, refill, tokens, last, now), capacity)
    | LB { capacity, leak, level, last } =>
        let
          val lvl = lbLeak (leak, level, last, now)
        in
          clampFloor (Real.fromInt capacity - lvl, capacity)
        end
    | SW { limit, window, winStart, cur, prev } =>
        let
          val { estimate, ... } =
            swRoll (limit, window, winStart, cur, prev, now)
        in
          clampFloor (Real.fromInt limit - estimate, limit)
        end
end
