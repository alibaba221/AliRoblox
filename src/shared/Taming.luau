--[[
	SicilyShared.Taming
	Rules for breaking in a wild horse, shared so the server (authoritative) and every client
	(animation, UI prediction) agree.

	When a player mounts a wild horse, the server picks a seed. From it everyone derives the same
	timeline of struggles: bucks (hind kicks), rears, spins, lunges and head shakes. The rider
	presses E (gamepad Y / tap on mobile) to calm the horse: each press adds progress, progress
	drains over time and every big buck knocks some off. Reach 1 and the horse is tamed; drop to 0
	(or run out of time) and it throws you.
]]

local Taming = {}

local KINDS = {
	{ Kind = "Buck", Weight = 0.34, Duration = 0.75, Knock = 1.0 },
	{ Kind = "Rear", Weight = 0.2, Duration = 1.1, Knock = 0.9 },
	{ Kind = "Spin", Weight = 0.24, Duration = 1.05, Knock = 0.6 },
	{ Kind = "Lunge", Weight = 0.12, Duration = 0.8, Knock = 0.5 },
	{ Kind = "Shake", Weight = 0.1, Duration = 0.6, Knock = 0.3 },
}

-- Seconds after the mount starts before the horse starts fighting (the climb-on animation).
Taming.Delay = 0.9

local function pickKind(rng: Random)
	local total = 0
	for _, k in KINDS do
		total += k.Weight
	end
	local roll = rng:NextNumber() * total
	for _, k in KINDS do
		roll -= k.Weight
		if roll <= 0 then
			return k
		end
	end
	return KINDS[1]
end

--[[
	Timeline of struggle events { Start, Duration, Kind, Side (-1|1), Strength, Impact } in seconds
	since the taming started. Deterministic for a given seed + temperament.
]]
function Taming.Timeline(seed: number, temperament)
	local rules = temperament.Taming
	local rng = Random.new(seed)
	local events = {}
	local t = Taming.Delay + rng:NextNumber(0.1, 0.4)
	local rate = math.max(rules.BuckRate, 0.1)
	while t < rules.MaxDuration + 2 do
		local kind = pickKind(rng)
		local duration = kind.Duration * rng:NextNumber(0.85, 1.2)
		local event = {
			Start = t,
			Duration = duration,
			Kind = kind.Kind,
			Side = if rng:NextNumber() < 0.5 then -1 else 1,
			Strength = rng:NextNumber(0.75, 1.2),
			Knock = kind.Knock,
			Impact = t + duration * 0.45,
		}
		table.insert(events, event)
		-- a breather now and then so the rider can make progress
		local gap = (1 / rate) * rng:NextNumber(0.35, 1.0)
		if rng:NextNumber() < 0.18 then
			gap += rng:NextNumber(0.6, 1.2)
		end
		t += duration + gap
	end
	return events
end

-- Progress after `dt` seconds with no input (elapsed = time since taming started).
function Taming.Drain(progress: number, dt: number, elapsed: number, temperament): number
	local rules = temperament.Taming
	if elapsed < Taming.Delay + rules.GraceTime then
		return progress
	end
	return progress - rules.Decay * dt
end

-- Progress after one calming press (a little less effective near the end).
function Taming.Press(progress: number, temperament): number
	local rules = temperament.Taming
	return progress + rules.PressGain * (1 - 0.3 * math.clamp(progress, 0, 1))
end

-- Progress lost when an event's impact lands.
function Taming.Knock(event, temperament): number
	return temperament.Taming.BuckKnock * event.Knock * event.Strength
end

-- Minimum seconds between counted presses (anti auto-clicker; ~12 presses/s max).
Taming.PressInterval = 0.08

local function envelope(t: number, duration: number): number
	-- quick attack, hold, soft release
	local u = t / duration
	if u <= 0 or u >= 1 then
		return 0
	end
	local attack = math.clamp(u / 0.2, 0, 1)
	local release = math.clamp((1 - u) / 0.35, 0, 1)
	local a = attack * attack * (3 - 2 * attack)
	local r = release * release * (3 - 2 * release)
	return math.min(a, r)
end

--[[
	What the horse is doing `elapsed` seconds into taming, for animation and movement:
	{ Rear = 0..1, Buck = 0..1, Kick = 0..1, Spin = -1..1 (turn), Lunge = 0..1, Shake = -1..1,
	  Intensity = 0..1 }
]]
function Taming.Sample(timeline, elapsed: number)
	local sample = { Rear = 0, Buck = 0, Kick = 0, Spin = 0, Lunge = 0, Shake = 0, Intensity = 0 }
	for _, e in timeline do
		if elapsed >= e.Start and elapsed <= e.Start + e.Duration then
			local k = envelope(elapsed - e.Start, e.Duration) * e.Strength
			if e.Kind == "Buck" then
				local u = (elapsed - e.Start) / e.Duration
				sample.Buck = math.max(sample.Buck, k)
				sample.Kick = math.max(sample.Kick, k * math.clamp(math.sin(u * math.pi * 2), 0, 1))
			elseif e.Kind == "Rear" then
				sample.Rear = math.max(sample.Rear, k)
			elseif e.Kind == "Spin" then
				sample.Spin += k * e.Side
			elseif e.Kind == "Lunge" then
				sample.Lunge = math.max(sample.Lunge, k)
			elseif e.Kind == "Shake" then
				sample.Shake += k * e.Side * math.sin((elapsed - e.Start) * 22)
			end
			sample.Intensity = math.max(sample.Intensity, k)
		elseif e.Start > elapsed then
			break
		end
	end
	sample.Rear = math.min(sample.Rear, 1)
	sample.Buck = math.min(sample.Buck, 1)
	return sample
end

return Taming
