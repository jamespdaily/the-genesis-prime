//// A player's casts, a feature of the game connection's rule
//// (genesis_prime/game/connection) as movement and chat are: the press of an
//// ability on the action bar, the answers the client expects, the cast bar and
//// cooldowns it keeps, the cast's go and finish, the child casts a Proxy effect
//// starts, the thresholds of a RapidTap or ChargeRelease ability, and the cast's
//// end when the client cancels it. The caster's connection owns its casts and
//// sends every message about them; it tells the connections that see its player
//// the same news, which they write for a cast they know.
////
//// ```
//// client                    connection (this rule)                         viewers' connections
//// 0x9a press ──────────────▶ decode; bag index ─▶ the ability's tree (genesis_prime/game/spell_plan)
////                            an open threshold of the ability ─▶ the stage its index names
////                            a refusal of the client's own checks ──▶ 0x7fc {client id, Spell4 id, result}
////                            the spell's cast conditions last (CasterCast 151, TargetCast 281)
////                            accepted: id k = mint(unit, n); the gcd starts
//// ◀── 0x7fd {client id, k, caster}                  (the caster's cast starts in its client)
////                            Tell(each viewer, CastStarted)  ──────────────▶ 0x7ff, when its client shows the caster
//// ◀── 0x816 {ability, ability, 0, k}   a RapidTap or ChargeRelease ability's first press opens its threshold
//// ◀── 0x817 {ability, index}           the next tap's stage, or the next charge level (a timer)
////                            cast time 0: the go at once; else StartTimer(go)
//// ◀── 0x7f4 {k, phase 0, no target, no effect}  ◀── Tell(each viewer, CastWent) ─▶ 0x7f4, for a cast it wrote
////                            the spell's own cooldown starts at the go its method names
////                            each Proxy of the phase: StartTimer(delay), or at once for delay 0
////                            a child: id k2 = mint, root = the pressed spell, parent = the proxying spell
//// ◀── 0x7ff {k2, ..}        Tell(each viewer, CastStarted) ───────────────▶ 0x7ff
//// ◀── 0x7f4, 0x7fe          its go and finish, as the pressed cast's
//// ◀── 0x7fe {k}             Tell(each viewer, CastFinished) ──────────────▶ 0x7fe, for a cast it wrote
//// ◀── 0x814 {ability, bit}  the last tap or the release closes the threshold
//// 0x801 {k, 6, 1} ─────────▶ the cast ends: its timers cancelled, 0x7fe to all
////
//// each input in the world ─▶ `persisted`: a lasting cast whose persistence stopped holding
////                            ends ──▶ 0x7f9 {k, 282 or 283, caster, 0}, then 0x7fe {k}; Tell(each viewer, CastFinished)
////
//// each input ─────────────▶ `settled`: the stealth change ──▶ StealthChanged (0x8f5), then the procs held for the
////                            input's events (Died or LeftCombat, then EnteredStealth or LeftStealth) cast
////                            their spells ──▶ 0x7ff {k, root and parent the holder's spell}, no 0x7fd
////
//// 0x4db held 1 ────────────▶ the ability is held: the same press, with the id k minted and no 0x7fd
////                            its cast over and its cooldowns run ─▶ the same press again (StartTimer(repeat))
//// 0x4db held 0 ────────────▶ the ability is not held: the repeat timer cancelled; a charge fires its stage
//// ```
////
//// - **The press** is 0x9a inside 0x038C: the client's cast id, the ability's bag
////   index, the target and the press bit (`opcode.0x9a`). A cast id of 0 is one
////   the client never sends, and ends the connection. A press bit of 0 is a
////   console setting's; the press is logged and ignored. A bag index the player
////   does not hold is answered 0x7fc with Spell4 id 0 and result 4
////   (`0x14039a040`; the server's choice, which the client allows).
//// - **The hold** is 0x4db: the client sends it instead of 0x9a under its default
////   hold-to-continue-casting setting, once with held 1 at key down and once with
////   held 0 at key up, with no cast id of its own (`opcode.0x4db`). A held 1 is the
////   same press as a 0x9a's with two differences: the server mints the cast id and
////   writes 0x7ff in place of 0x7fd (a 0x7fd names a pending cast the client does
////   not make), and a refusal is a 0x7fc with client cast id 0
////   (`cast.hold_answer`). The client holds no repeat timer, so while the key is
////   held the server casts the ability again, when its last cast is over and the
////   global cooldown it started and the ability's own cooldown have ended, on a
////   timer of the rule; a press behind another cast waits for its end, never
////   refused 13, which the client hides under the setting (`cast.hold_repeat`; the
////   server's choice). A second ability's held 1 replaces the held one, and a second
////   held 1 of the held ability is the same hold. Held 0 ends the repeats and cuts
////   no cast or channel short; for a ChargeRelease ability it fires the charged
////   stage, and a RapidTap ability's repeats are its next stages inside its
////   threshold (`cast.hold_by_method`, `cast.hold_stop`). A refused repeat ends the
////   hold, and so does a 0x801 naming the hold's last cast (the server's choice: a
////   cancel is the player's intent to stop, so a cancelled charge neither restarts
////   nor fires at the held 0 that follows). A bag index with no ability is answered as a 0x9a's is.
//// - **The target** of every cast is the caster: no level-1 ability needs a
////   target the client picks (`Spell4TargetMechanics.targetType`: the client makes
////   the caster the target of a spell of kind 0, 2, 6 or 7 before it sends), so
////   the press's target is not read, and the target checks of the client (91, 105)
////   wait for the first ability that needs one. Who a spell strikes is the area its
////   effects name, which a later step reads.
//// - **The refusals** are the client's own checks, answered 0x7fc with the
////   client's result and clearing the client's global cooldown: 57 for a dead
////   caster's press of a spell whose caster condition row has the dead bit, and
////   58 for a living caster's press of one whose row asks for a dead caster
////   (`Spell4.spell4ConditionsIdCaster`, `cast.dead_player`; the row's other
////   conditions are not checked); 13 while the
////   caster's current cast is live (below); 14 while the global cooldown has more
////   than 500 ms left, for kinds 0 and 2; 15 while the spell's own cooldown has
////   more than 500 ms left (`0x1403b14c0`); a caster requirement's result when the
////   caster's resource fails it and the spell's waiver does not pass (`0x1403b1780`,
////   `Rampage` 51 below 250 Kinetic Energy unless the caster is under Overdrive 42908);
////   50 + the resource slot for a cost the caster's class
////   resource cannot pay (`0x1403b3320`, `0x1405e7980`,
////   `Spell4CastResult.vital_cost`); 169 for a spell that needs the weapon when
////   slot 16 holds none (`0x1403afb10`); 151 for a spell whose CasterCast fails and
////   281 for one whose TargetCast does, the last checks of the press (`0x1403ace00`,
////   below); and 285 for a spell whose method is not
////   one of Normal, Multiphase, Channeled, RapidTap and ChargeRelease
////   (`Spell.CodeEnumCastMethod`). A cost in a vital the server does not hold, a cast
////   condition it cannot read and a method not built are each logged once on the
////   connection for the coverage measure. The caster's checks run in the client's
////   order (`Verdict`).
//// - **The cast conditions** are the spell's prerequisiteIdCasterCast and
////   prerequisiteIdTargetCast, which the client checks after every other check of the
////   press, CasterCast first (`0x1403ace00`, `Spell4.prerequisiteIdCasterCast`), so a press
////   that fails several gets the client's first failure; the check runs only on the path
////   that would accept, since a press the client queues (317) is sent unchecked. The first
////   unit is the caster, and the second unit too: the server reads no target and the client
////   makes the caster the target of every spell it presses. A press held for a cooldown or
////   behind the current cast is checked when it starts, as one the client sent unchecked is
////   (`Spell4.prerequisiteIdCasterCast`), and a held key's repeat each time. A spell with a
////   caster requirement block and propertyFlags bit 2 is not gated by its CasterCast: that
////   prerequisite only waives a failed requirement (`0x1403b1780`). A condition of a type
////   the server does not read, or a type 37 roll (a press draws none), refuses with the
////   check's result and a warning once for the spell (the server's choice, as for a cost in
////   a vital it does not hold).
//// - **A cost is checked at the accept and paid at the cast's first go** (`Pay`): the
////   client checks a cost only before it sends a press, lowers no resource itself and
////   shows only what 0x935 says, so when to pay is the server's
////   (`Spell4.innateCost0.timing`), and a retail video shows the Actuators of Gamma
////   Rays dropping when its beams go off. The accept checks the costs against the slot
////   less what the live casts have reserved (`unreserved`) and keeps them on its live
////   cast (`Live.reserved`); the first go pays them as its strike begins, so the round's
////   hits are always paid for and the go's gates and gains read the paid caster, as
////   one 0x935. A cast that ends before its first go (a 0x801, death, leaving) pays
////   nothing, and its reservation ends with it. A spell whose first go is at once, or
////   that has no go of its own, pays at its accept, in the step of its check
////   (`pays_at_accept`). A second press taken in the same step is checked against what
////   the first left (genesis_prime/game/class_resource).
//// - **A spend of every point held** (`spell_plan.SpendAllCost`, genesis_prime/game/spend):
////   the check is of the base cost alone, as the client's is (`0x1403b3320`), and the
////   accept then reserves every whole point the slot holds less the reserved, which the
////   first go takes and whose new value the client is sent (`opcode.0x935`). The points
////   above the base cost are the cast's n, fixed at the accept (at the start of a held
////   press, which is checked and reserved then), kept on
////   the live cast, and read at each go: the go's strike (`GoAsked.spent`), gains and
////   Proxies are the ones whose tag holds for n. A child a Proxy starts has no n and
////   keeps every effect. A cost with an EMM id the server does not read
////   (`spell_plan.UnreadSpendCost`) is refused with the cost's result and logged once.
//// - **The current cast** is the client's: a cast whose spell shows a cast bar
////   (`spell_plan.shows_cast_bar`) is the caster's current cast from its start. Its
////   go clears it for a Normal cast with a cast time and no parent, and a cast
////   that is itself the current cast clears it at its go unless its method is
////   Multiphase, ChargeRelease or PressHold or it is a channel; any cast's finish
////   clears it, and a 0x801 clears it whatever cast it names. The client refuses
////   a press with 13 only against it, and not when its spell is free while live or
////   the pressed spell ignores casting (`cast.current_cast`, `Spell4.propertyFlags`,
////   `0x1403afb10`). The server keeps the same in `current`.
//// - **A press during the current cast is the server's choice.** The client itself
////   never refuses an ability press with 13 and never queues one behind its current
////   cast: its casting test runs only for a request whose word 0x14 is non-zero,
////   which a press leaves 0 (`cast.press_queue`). The server models that unused test
////   with the same window as the cooldown queue: a press with more than 500 ms of
////   the current cast left (its start plus its duration, `spell_plan.duration_ms`,
////   less the time now) is refused 13, and one with 500 ms or less left is held and
////   starts at the go or finish that clears the current cast, not from a timer. A
////   cast that has no end of its own, a charge held until its release, always
////   refuses.
//// - **A press within 500 ms of a cooldown's end** is held: the client queues it
////   (317) and sends it (`0x1403b14c0`), so the server starts it when the
////   cooldown ends, from a timer, and answers nothing before. A second press
////   while one is held is refused 13 (the server's choice). The held press keeps
////   the stage it resolved to when it came, as the client does. The release of a
////   ChargeRelease threshold is resolved before any caster check, so a held press
////   neither refuses it nor is changed by it (`0x1403bfd60`).
//// - **The cast id** is 2^31 + unit id x 2^11 + n mod 2^11, skipping an id a live
////   cast of the caster holds: unique among the live casts of every unit, since
////   the client keeps one table of casts (`0x140561c30`) and unit ids are below
////   2^20, and never 0. The client's own counter makes no collision: its
////   pending casts live apart (`cast.pending_table`). A child takes the next id.
//// - **The cast bar and cooldowns** are the client's own: 0x7fd and 0x7ff start
////   the caster's global cooldown (`0x14046afc0`, kinds 0 and 1), and a go starts
////   the spell's own (`0x14046b1e0`), so the server sends no 0x804. The server
////   keeps the same, to refuse what the client would: the global cooldown from the
////   accept for the SpellCoolDown time, the spell's own where its method says
////   (`spell_plan.CooldownStart`, `0x14053e5a0`), the child casts none (kind 3).
//// - **The go** is 0x7f4 with the cast id, the ignore-cooldown bit 0, the caster's
////   place as the destination, no target, no position and no missile, and the
////   phase (`opcode.0x7f4`): a go that names no target carries no damage, which
////   the next step adds. A Multiphase spell's phase is the phase's index and a
////   channel's the pulse's (`opcode.0x7f4.phase`). Each go is followed by the
////   spell's Proxies of that phase, and the finish, 0x7fe, comes after the last go,
////   at once for a spell that is not Multiphase, and for a channel at its
////   channelMaxTime from a timer of its own.
//// - **A go's gains** (`Gain`) are the spell's own gains of the phase and, once
////   for the go and not once per unit, the gains of each Proxy of the phase aimed
////   at each struck unit when the round has a Hit and the Proxy's gate passes
////   (`spell_plan.Gain`). Each is given when its prerequisite passes against the
////   caster (genesis_prime/game/prerequisite): the spells of the caster's own live
////   casts whose primary target it is, whether it is in combat, its health, shield
////   and the class resource slot it holds as the vitals 1, 3 and 5 to 11, and the
////   rolls the connection drew. A prerequisite of a type or a vital not read, and a
////   ticking gain, give nothing and a debug line. A creature's cast on the player is not
////   held here, so a prerequisite cannot find one (no kit prerequisite tests a
////   creature's spell).
//// - **A go's gates read the caster as it stood before the go's own effects.** The
////   gates of its Proxies and of its gains see the live casts with this go counted,
////   but not the children the go starts and not the cast's removal at its finish: a
////   server choice, since the client applies no Proxy itself
////   (`Spell4Effects.effectType.26.dataBits06`). A gain that asks to be "not under"
////   a spell this same go starts is given (`cast_gate_test`).
//// - **A go's lasting effects** (genesis_prime/game/lasting): each Fluff (17), Scale (18),
////   RavelSignal (81) and SpellForceRemove (80) effect of the phase whose gate against the
////   caster passes is listed in the target info of each unit its targetFlags aim at, with
////   the effect's delay, a result bit, the instance count 1 and the lifetime 0 the client
////   works out itself; a unit the round did not strike gets an info of its own
////   (`opcode.0x7f4.target_info`, `opcode.0x7f4.effect_time`). A Fluff, Scale or
////   RavelSignal effect gives the unit a node of the cast that lives as long as its
////   longest effect, kept on the live cast; a type 80 effect takes the matching nodes of the caster's casts off the
////   unit, oldest cast first, each written 0x811 (`opcode.0x811`); and a cast that
////   gives a unit a node it holds none on takes off the caster's oldest casts of its
////   stack at the stack's cap (Jim's decision, `Spell4StackGroup.stackCap`).
//// - **A go's property modifiers** (genesis_prime/game/unit_properties): each type 11
////   and type 145 effect of the phase that has a life (a durationTime, or flags bit 2) and
////   whose gate against the caster passes is listed on the caster like a Fluff effect, gives the
////   caster's node its life, and starts at the go plus its delay and ends after its
////   duration, as `CasterChangeStarts` and `CasterChangeEnds` for the connection to apply to the
////   player's properties. A modifier ends on a timer of its own and not with the node's
////   time (a node can outlive it, or end before it when the spell takes the larger of
////   delay and duration); taking the cast's node off the caster ends its modifiers and
////   cancels their timers; the caster's death ends every modifier of its casts but the
////   innate passive's, and every one still pending but the passive's; a later go of the cast arms each again from that go; the player
////   leaving ends none, since the connection's properties go with its player. These
////   are the server's choices: the client works out no property.
//// - **A go's property modifiers on creatures** (type 11 rows with targetFlags 2, 4 or 6,
////   a `StruckChange`): each is aimed at the creatures the go hit, in the life and at the
////   time the go struck them (`HitCreature`), listed on each like a Fluff effect and
////   giving its node the row's life. The cast owns the time and the creature the values:
////   the rule tells the creature `TargetChangeStarts` at the go plus the row's delay, in
////   the go's own step when there is none, and keeps what it started in `on_creatures`.
////   It has no end timer of its own: it ends, as `TargetChangeEnds` told once, when the
////   cast's node on that creature ends by time, is taken off by a type 80 removal or a
////   push off by the stack rule, when the creature leaves the caster's sight, when the
////   cast's persistence stops holding, when the caster dies (but for the innate passive's
////   cast) and when the player leaves; a start still waiting for its delay is cancelled
////   with it and told nothing. A later go of the cast on the same creature starts it
////   again from that go. A row aimed at another player is left out until a modifier on
////   another player is built (#570), and the stacking of casters' modifiers on one
////   creature is not built (#569).
//// - **A go's disguises** (genesis_prime/game/look): each type 112 effect of the phase
////   that has a life and whose gate against the caster passes is a modifier row whose change is a
////   `Look`, so it is listed, started, ended, cancelled with the node and ended at death
////   by the modifiers' rules above, as `CasterChangeStarts` and `CasterChangeEnds`; the
////   connection turns them into the player's 0x933 and its viewers' `LookChanged`
////   (genesis_prime/game/connection/look). The rule keeps no look: two disguises on one
////   slot, the base and what shows are the look's.
//// - **A go's Interrupt Armor** (`Spell4Effects.effectType.52`): each ModifyInterruptArmor
////   row of the phase that reaches the caster (genesis_prime/game/spell_plan
////   `PropertyModifier.armor`) is a property modifier of property 44, the armor's maximum,
////   and goes through every rule of the property modifiers above: the same listing, node
////   life, start, timer, end and removal. The player's armor follows its maximum
////   (genesis_prime/game/player_life `armor_followed`), so the rule asks nothing more of
////   the connection for it. The client has no case for the effect, so the armor and its
////   maximum are the server's (`Spell4Effects.effectType.52`,
////   `opcode.0x938.interrupt_armor`).
//// - **A go's shield heals** (`Spell4Effects.effectType.118`): each HealShields effect of the
////   phase that reaches the caster (genesis_prime/game/spell_plan `ShieldHeal`) whose gate
////   against the caster passes is listed in the caster's target info with a damage
////   description of its amount (type HealShields, result Hit, the amount as the raw, the
////   scaled raw and the health change), which the client shows as a floater and a combat
////   log line and never applies. The amount is worked out at the go from the caster's own
////   shield, health and stats as they stood before the go's own effects
////   (genesis_prime/game/damage `amount_on_caster`: Energize is 0.3 of the missing
////   shield), and lands at the go plus the row's delay as `CasterChangeStarts` with a
////   `ShieldHeal` change, for the connection to raise the player's shield by
////   (genesis_prime/game/player_life `shield_healed`): in the go's step, after its 0x7f4,
////   with no delay, else on a timer. A heal gives the caster's node a life of its delay, so
////   the 0x7fe waits for it; when the node's end and a pending heal are due in the same
////   millisecond the end lands the heal first. A node taken off the caster, a persistence
////   that stops holding and the caster's death drop a pending heal with its timer; a later
////   go of the cast heals again and cancels no earlier heal. A periodic heal (a
////   tickTime) is not applied, and a debug line says so: each tick needs a 0x7f8. The
////   server rolls no critical for a heal: the description is always a Hit, so the seed
////   draws nothing for it (the server's choice).
//// - **A go's absorbs** (`Spell4Effects.effectType.29`): each Absorption effect of the phase
////   that reaches the caster, has a lifetime (a durationTime, or flags bit 2), is not
////   periodic and whose gate against the caster passes is listed in the caster's target
////   info like a Fluff effect, gives the caster's node its life, and starts a pool on
////   the caster, as a shield heal and a property modifier do, from the amount worked out at
////   the go from the caster's stats as they stood before the go's own effects
////   (genesis_prime/game/damage). The plan reads a type 29 row as a property modifier row
////   whose change is an `AbsorbChange` (genesis_prime/game/spell_plan), so it goes
////   through the same listing, node life, timers, end and removal. The sequence of one go:
////
////   ```
////   go ─▶ 0x7f4 lists the row on the caster
////      ─▶ no delay: CasterChangeStarts(source, Absorb(amount, mask)) in the go's step, after its 0x7f4
////         delay:    a ModifierStart timer of the delay
////      ─▶ ModifierEnd timer at delay + duration, none for flags bit 2
////   ModifierStart fires ─▶ CasterChangeStarts(source, Absorb(amount, mask))
////   ModifierEnd fires   ─▶ CasterChangeEnds(source)
////   ```
////
////   A pool ends on a timer of its own, as a property modifier does, and the connection
////   ends it by source (genesis_prime/game/connection/absorption), where a pool the
////   hit rule used up is already gone and the end writes nothing: the cast keeps its
////   node's time when its pool is spent (a server choice). Taking the cast's node off
////   the caster ends the pool of each row and cancels its timers; the caster's death
////   ends every pool of its casts and cancels the pending ones, after the life dropped
////   them; the player leaving ends none, since the life goes with its `Entered`; a later go
////   of the cast arms each pool again from that go, which refills a pool still held.
//// - **A go's forced moves** (`Spell4Effects.effectType.3.player`): each type 3 effect of
////   the phase aimed at the caster whose gate against the caster passes is listed in the
////   caster's target info with its delay, and nothing more: the caster's client works out
////   the destination, moves its own unit and reports the move in its next 0x637, which
////   the movement rule takes as any other. A forced move gives no node a life, starts no
////   timer and changes no property.
//// - **A go's cooldown effects** (`Spell4Effects.effectType.73`,
////   genesis_prime/game/cooldown): the spell's own cooldown and a stage's ability
////   cooldown start before the go's effects apply, as in the client (`0x14053e5a0`), so
////   a type 73 effect of the phase aimed at the caster whose gate passes already sees
////   them. It is listed in the caster's target info with its delay, and it changes the
////   running cooldowns it picks at the go plus its delay: in the go's step with no
////   delay, on a timer with one. An effect whose lifetime (delay plus duration, the
////   larger of the two for a spell with the record flag 0x10000000, never ending with
////   flags bit 2) ends after its start is also kept for the cooldowns that start later
////   and dropped on a timer at the end of its lifetime; any other acts once
////   (`0x14046b7f0`, `opcode.0x7f4.effect_time`). Every such effect gives the caster's
////   node its lifetime, so the 0x7fe, which destroys the effects still pending
////   (`opcode.0x7fe`), waits for them; when the node's end and a pending start are due
////   in the same millisecond the end applies the start first. Taking the cast's node
////   off the caster, the caster's death and its leaving drop the kept effects and
////   cancel their timers, pending starts included, and a later go of the cast keeps
////   each again from that go; the cooldowns an effect changed stay changed. The global cooldown is never changed (`0x14046b920`) and the server sends
////   no 0x804, which would undo the change. After a change a press held for a cooldown's
////   end and the hold's repeat wait for the new end, a timer of 0 ms when it ended: the
////   server's choice. Group cooldowns are not kept.
//// - **A player's stealth** is the Stealth rows (effect type 83) its casts hold on it,
////   by cast id and effect id (`State.stealth`), kept with whether damage ends each
////   (`spell_plan.Breaks`); the player is stealthed while it holds any (`stealthed`).
////   A go lists each Stealth row of its phase whose gate passes against the caster in
////   the caster's target info and holds the caster's node until it is removed (a Stealth
////   row with no durationTime lasts until removed), and adds its source; a RemoveStealth
////   row (type 84) ends every source. After the go's effects, a spell whose
////   `stealth_change` ends stealth at that go (value 0 at each go, value 1 at the cast's
////   last) ends every source of the other casts (`Spell4.spellCastStealthChange.break`;
////   the server's rule): the cast of each loses its node on the caster as a type 80 removal takes it off (0x811, and
////   the 0x7fe of a lingering cast of a method the client keeps, `node_off`; a Normal
////   cast the client destroys with the 0x811), so the buff that stands for the stealth
////   never outlives it. A node that leaves the caster takes its cast's sources
////   with it (`effects_ended`), `damage_taken` ends the sources damage breaks, and
////   death and leaving drop all. Each input (a press, a timer, a go, the player's death,
////   a blow) compares the stealth before and after and ends with one `StealthChanged`
////   when it moved, so the connection's 0x8f5 follows the 0x811 and 0x7fe it causes and
////   precedes the procs it fires. A
////   caster's type 116 prerequisite reads the stealth as it stood before the go's own
////   effects, as every gate does (`subject_of`).
//// - **A player's procs** are the Proc rows (effect type 14, `spell_plan.ProcRow`) its casts hold on
////   it, by cast id and effect id (`State.procs`), each with the times it fired at. A go lists each
////   Proc row of its phase whose gate passes in the caster's target info and holds the caster's node
////   until the row's life ends, as a Stealth row does (`Spell4Effects.effectType.14.lifetime`), and
////   adds its source; a source leaves where a stealth source leaves (`effects_ended`), at the
////   caster's death but for the innate passive's, and at leaving. Each input ends in `settled`,
////   which lists its events, the input's own (`Died` for `died`, `LeftCombat` for `combat_left`)
////   and then its stealth change (`EnteredStealth` or `LeftStealth`), and, after the
////   `StealthChanged` it emits, casts the spell of each proc held when the input's own work was
////   done whose trigger is among them, in event order and then source order (the server's choice,
////   `Spell4Effects.effectType.14.dataBits00.217_218`, `.0_44`): a proc whose node the same input
////   took off does not fire, and one the input applied does. The cast starts as a child's does,
////   from the caster at itself (dataBits03 1 and 9 alike, `Spell4Effects.effectType.14.dataBits03`):
////   a 0x7ff with the holder's spell as root and parent and no 0x7fd (`opcode.0x7ff.root_parent`).
////   Its go and finish are inputs of their own, so its own stealth change fires procs too. A proc
////   fires at most `count` times in any `window_ms`, counted from the fires the rule keeps, and a
////   fire exactly `window_ms` after the last is allowed (`Spell4Effects.effectType.14.limits`; the
////   server's choice of the edge). A spell whose caster condition refuses the caster's life (row 1,
////   mask 225, refuses a dead caster: `Spell4.spell4ConditionsIdCaster`, `cast.dead_player`) does
////   not fire and records no fire, with a debug line. The chance is 1.0 and draws no roll. A death
////   leaves the passive's procs with the passive and ends every other cast before the procs are
////   matched, so a `Died` proc of any other cast is never held: its go writes a debug line (the
////   plan cannot tell the passive, so the rule enforces it, `procs_held`); a camp drops the procs
////   and their fire times.
//// - **A cast that lingers** is one whose last go has gone while a node of it still
////   has life: every step of its end runs (the current cast cleared, a channel's
////   cooldown, a stage's threshold closed) and only its 0x7fe waits, since the client
////   ends no buff on time (`cast.target_node_end`). A timer of the rule ends the
////   nodes as their time runs out, 0x811 for the units whose node ends and the 0x7fe
////   with the last. A lingering cast holds its id until then. A live cast's nodes end
////   on the same timer, 0x811 for the unit while the cast goes on, and a 0x801 stops a
////   cast the same way: its pending gos are cancelled and it lingers if a node has life
////   left, since a cancel ends no buff.
//// - **Persistence** is the server's alone: the client never evaluates
////   prerequisiteIdCasterPersistence or prerequisiteIdTargetPersistence, which it keeps
////   to word the results 282 and 283 (`Spell4.prerequisiteIdCasterPersistence`,
////   `0x1405648a0`). The connection calls `persisted` at the end of each input of a player
////   in the world, which is exact and needs no timer or interval (the tables give none).
////   Each live or lingering cast, lowest id first, whose spell's condition fails ends
////   (checked again after each end, since one can break another's): 0x7f9 {cast id, 282 or
////   283, the caster, 0}, which destroys the nodes the cast holds so its buff goes and leaves
////   the cast filed, then the 0x7fe that takes it out of the client's table, told to the
////   audience as a finish (`opcode.0x7f9`, `cast.target_node_end`; which message retail sent
////   is not known). The cast's go, finish and NodesEnd timers are cancelled, its property
////   modifiers and cooldown effects end, its stealth sources drop (the input's last effect
////   is `StealthChanged`), the current cast clears when it was this one, an open threshold
////   it is the base cast of closes as a 0x801 closes it, and a press held for the clear
////   starts. CasterPersistence (282) is checked before TargetPersistence (283), the caster
////   the first unit and the cast's primary target the second; TargetPersistence is checked
////   only for a cast whose primary target is the caster, since the connection holds no
////   creature's state. A condition of a type not read, a roll and a creature target keep the
////   cast, with one debug line for the spell.
//// - **A unit that leaves the caster's sight** takes its nodes with it on the client
////   (`0x1404550d0`), so the rule drops them too and a lingering cast left with no node
////   ends with its 0x7fe (`unit_removed`).
//// - **A go's rolls** are one for each type 37 condition among the gates of the
////   Proxies that start a child, of the gains that may be given and of the lasting
////   effects of the phase (`rolls_needed`); the connection draws that many from its seed before it calls
////   `went`, and none when there is no such condition, so no other roll of the
////   connection moves.
//// - **A child cast** is the Proxy's spell cast as its own, from the caster, with
////   root the pressed spell and parent the spell whose Proxy fired
////   (`opcode.0x7ff.root_parent`), after the Proxy's delay from the parent's go;
////   its 0x7ff goes to the caster too. Its go and finish follow as a pressed
////   cast's, and it starts no global cooldown (kind 3). A Proxy behind a caster
////   apply prerequisite or one its dataBits06 names starts only when each passes
////   against the caster at the go (`proxy_gates`). One behind a target apply
////   prerequisite as well starts a child on a unit only when that prerequisite passes
////   too, for each unit separately (`children`, `target_gate`): the target first and
////   the caster second (`Spell4Effects.prerequisiteIdTargetApply`), the struck unit as
////   the caster's picture shows it when the round closes (`went`'s `poses`; a unit it no
////   longer shows decides nothing and leaves a debug line), or the caster on its own
////   point for a Proxy aimed at it. The target gate takes no roll. A child's timer is
////   its own: the parent's finish
////   leaves the pending children, which start 100 ms after it (Crush), and only
////   the player leaving the world cancels them.
//// - **A RapidTap threshold** opens with the first tap's 0x816 and lasts the
////   ability's thresholdTime from a timer the server mirrors, since the client
////   closes it by itself then (`opcode.0x816`). Each later tap casts the stage at
////   the threshold's index, with root the ability and parent the ability
////   (`cast.stage_root_parent`), and the next index goes in 0x817; the last stage
////   closes the threshold with 0x814 and the bit set, which starts the ability's
////   cooldown. The window ending closes it, writes nothing and starts the cooldown
////   (`opcode.0x814`, `opcode.0x817`, `0x1403bfd60`).
//// - **A ChargeRelease threshold** opens with the first press's 0x816; the press's
////   cast, the base cast, stays live with no go until the release or a cancel
////   (`cast.charge_release_base`). Each later row's thresholdDuration after the
////   one before, a timer sends the next level in 0x817. The release is the next
////   press, which casts the row at the level reached; its first go starts the
////   ability's cooldown, and after its finish 0x814 closes the threshold and the
////   base cast ends with 0x7fe. The client marks the charge full at the ability's
////   thresholdTime and sends nothing, so the server holds the charge until a
////   release or a cancel.
//// - **The cancel** is 0x801: the server's cast id, a reason and a bit, which the
////   client sends as (6 or 11, 1) when the player's cast ends in its client, and
////   (0, 0) with the 0x816 value for an open ChargeRelease threshold
////   (`opcode.0x801`). It clears the caster's current cast, whatever cast that is,
////   and the cast ends with its go timers cancelled and 0x7fe to the caster and the
////   audience, no strike; the base cast of a charge ends its threshold too, with
////   0x814 before its 0x7fe. A cast that is not live is a debug line. Any other
////   reason or bit is one the client never sends, and ends the connection.
//// - **The audience** of a cast is the caster's viewers when it starts; its go and
////   finish go to them. A viewer writes a 0x7ff only when its client shows the
////   caster, and a go, or a finish, only for a cast it wrote
////   (genesis_prime/game/connection). The threshold messages go to the caster only.
//// - **Timers** are the connection's: this rule starts them with ids from
////   `first_timer`, one for each go, finish, child, held press, threshold window
////   and charge level waiting, and owns the ids from there up (`owns`).
////
//// - **The innate passive** is a cast the client never makes: `passive_started` starts it
////   at each join with a 0x7ff and no 0x7fd, as `Passive`, which starts no global
////   cooldown, is never the current cast, opens no threshold and runs no check of the
////   caster. Its go runs as any cast's, and the cast lingers with no 0x7fe, even when
////   no node of it lives, for the whole stay. The three passives hold caster condition
////   row 4 (mask 0: alive or dead) and propertyFlags 0x100 (the cast stays when its
////   caster is removed), so a death leaves it with its nodes and modifiers
////   (`Class.spell4IdInnateAbilityPassive00`, `Spell4.spell4ConditionsIdCaster`;
////   the server's choice for what death does to a cast no press made), and a camp, which
////   leaves every cast, drops it, so the next join starts it again.
////
//// What happens at each failure point of a cast:
////
//// | Point | What happens |
//// |---|---|
//// | a 0x9a body the client's reader refuses, or a cast id of 0 | the connection ends, nothing written |
//// | a 0x4db body the client's reader refuses | the connection ends, nothing written |
//// | a 0x4db whose bag index holds no ability | 0x7fc {0, 0, 4} for held 1, a debug line for held 0 |
//// | a 0x4db held 1 of the ability already held | the same hold: nothing written |
//// | a held cast refused, at the first press or a repeat | the 0x7fc, and the hold ends |
//// | the repeat timer fires after the release | nothing: the release cancelled it, and a firing that was already sent finds no hold |
//// | a press whose bag index the player does not hold | 0x7fc {client id, 0, 4} |
//// | a press past the last stage of an open threshold | 0x7fc {client id, the ability, 4} |
//// | a refusal of the client's own checks | 0x7fc with the result; nothing else changes |
//// | a spell whose cost has an EMM id the server does not read | 0x7fc with the cost's result, a warning once for the spell on the connection; nothing is paid |
//// | a cast with a cost ends before its first go: a 0x801, the caster's death or leaving | nothing is paid and nothing is sent for the cost; its reservation ends with the cast |
//// | a press needs points that a live cast has reserved | 0x7fc with the cost's result, as for a slot that holds too little |
//// | the slot holds less than a live cast reserved when its first go comes (the Esper's empty, the Warrior's drain) | the go pays what the slot holds, down to 0 |
//// | a 0x801 ends a cast while the round of its first go is open | the cost was paid as the strike began; the round's answer finds no live cast: no go is written, the hits stand |
//// | a press whose CasterCast or TargetCast fails | 0x7fc {client id, spell, 151 or 281}, after every other check; nothing else changes |
//// | a press whose cast condition is of a type the server does not read | 0x7fc 151 or 281, a warning once for the spell |
//// | a held press, or a held key's repeat, whose cast condition fails when it starts | 0x7fc {client id, or 0 for a key, spell, 151}; nothing started, a key's hold ends |
//// | a caster requirement fails and the spell's waiver passes | the requirement is waived; the next is checked |
//// | a caster requirement fails and its waiver is not read | 0x7fc with the requirement's result, a warning once for the spell |
//// | a lasting cast's persistence fails | 0x7f9 {cast id, 282 or 283, caster, 0}, 0x7fe, CastFinished to each viewer; timers and modifiers end; the current cast clears; a press held for it starts |
//// | a persistence not read, or a target persistence on a creature | the cast goes on; a debug line once for the spell |
//// | two casts whose persistence fails in one input, or one that fails because the other ended | both end in that input, the lower cast id first |
//// | a persistence check while the player is leaving or dead | nothing: `left` and `died` have already dropped every cast |
//// | a press while one is held | 0x7fc 13 |
//// | a go lists a shield heal while the caster's shield is full | the description is written with amount 0; the shield writes nothing (genesis_prime/game/player_life) |
//// | a heal's timer fires after its cast's node was taken off, the caster died or its persistence ended | no timer: it was cancelled with the node; nothing lands |
//// | a heal's start and its node's end fire in either order | the heal lands once, in the step of whichever is delivered first |
//// | a go lists an absorb and its connection restarts before the start | no pool: the connection enters with none and the client is created again |
//// | an absorb's start timer fires after its cast's node was taken off, the caster died or its persistence ended | no timer: it was cancelled with the node; nothing starts |
//// | an absorb's end timer fires after the pool was used up, or the death dropped it | the end writes nothing (genesis_prime/game/player_life) |
//// | a go of the cast arms its absorb while the earlier go's pool is held | the pool is refilled to the new amount, its end timer set again |
//// | an absorb's end and a blow reach the connection in one millisecond | arrival order: the pool soaks and then ends, or ends first |
//// | a go adds a Stealth source while the stack cap of its spell takes the first cast off | one source left, one 0x811, no `StealthChanged` |
//// | a go of a spell that ends stealth after the stealth ended | nothing to end, nothing written |
//// | a 0x801 ends a cast of `EndsStealthAfterLastGo` after one of its goes and before its last | the other casts' stealth ends as the cast stops, the 0x811 and the change after the cast's own end |
//// | a 0x801 ends a cast of `EndsStealthAfterLastGo` before its first go | the stealth stays held, nothing written |
//// | the caster dies stealthed | every cast ends, the sources drop, `StealthChanged` last |
//// | the player leaves stealthed | the sources drop, nothing is written |
//// | a proc's trigger happens inside its window | nothing is cast, no fire is recorded |
//// | a proc's trigger and the removal of its holder's node in one input | the removed proc does not fire: procs are matched after the input's work |
//// | a proc's trigger happens for a caster its spell's condition refuses (a dead caster) | a debug line naming the row and the spell, no cast and no fire recorded |
//// | a go of a cast that is not the innate passive applies a `Died` proc | the proc is not held, with a debug line: a death ends the cast before it could fire |
//// | the caster dies in combat | `combat_left`, then `died`: 63366 twice, each under its own limit |
//// | the caster camps or leaves stealthed | the procs drop with every cast, nothing is cast or written |
//// | a press with 500 ms or less of the current cast left | held, nothing written; taken at the go or finish that clears the current cast |
//// | a 0x801 for a cast that is not live, or one already finished | no change, a debug line |
//// | a 0x801 (0, 0) naming no open threshold | no change, a debug line |
//// | a 0x801 with a reason and bit the client never sends | the connection ends |
//// | a parent cast finishes with a child's timer pending | the child starts when its timer fires, with the root and parent it was made with |
//// | a threshold's window ends with taps left | the threshold closes, nothing is written, the cooldown starts |
//// | the player camps with casts, children or a threshold pending | every timer is cancelled and nothing is written: the viewers' clients drop the cast with the unit (the connection writes each viewer's 0x7fe before its 0x355) |
//// | the caster's connection ends, a key held | its timers and the hold end with it; the map's `Gone` removes the unit from each viewer, which finishes its casts first |
//// | the caster dies with casts live | each ends with its timers cancelled and 0x7fe to the caster and its audience; the hold and every other timer end, but the innate passive's cast, its nodes, modifiers and pending children (`died`) |
//// | the innate passive's plan is missing | a warning and no cast: the plans hold every class's passive, or the load fails |
//// | a timer fires after its cast ended | a go finds no live cast and does nothing; the cast's end cancels its go timers |
//// | a timer fires in a status that holds no player in the world | dropped; the world is left already |
//// | the answer of a store ask comes after a timer's due time | the timer is taken after the answer: the go and finish are late by the ask, never lost |
//// | a viewer is told a go or finish of a cast it did not write | dropped (genesis_prime/game/connection) |
//// | the audience's connection has ended | the tell is dropped by the shell |
//// | a go lists a lasting effect, the last go leaves a node with life | the cast lingers with no 0x7fe; the timer of its earliest ending node starts |
//// | a lingering cast's timer fires with no node ended, or after a removal took the cast off | nothing is written; the timer starts again for the nodes left, or finds no cast |
//// | two nodes of a lingering cast end at the same time | one 0x811 naming both units |
//// | a removal and a lingering cast's timer in one step | the removal first; the timer finds nothing |
//// | the caster dies with a lingering cast | its 0x7fe to the caster and the audience, with the live casts' (server choice: the client has no death path) |
//// | the caster leaves with a lingering cast | every timer is cancelled and nothing is written; each viewer's 0x355 ends the cast on its client |
//// | the client cancels a cast that holds a node with life left | its pending gos are cancelled and it lingers, with no 0x7fe until the node ends |
//// | a live cast's node ends while the cast goes on | 0x811 for the unit; the cast's later gos go on |
//// | a unit holding a node of a cast leaves the caster's sight | the node is dropped with no frame; a lingering cast left with no node ends with its 0x7fe |

import genesis_prime/client_connection.{type News}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/area
import genesis_prime/game/class_resource.{type Payment, type Resources, Payment}
import genesis_prime/game/cooldown
import genesis_prime/game/damage
import genesis_prime/game/hit
import genesis_prime/game/lasting
import genesis_prime/game/look
import genesis_prime/game/prerequisite
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/spell_plan.{type Plans, type Proxy, type Spell}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell
import genesis_prime/game/unit_properties
import genesis_prime/message/ability_hold
import genesis_prime/message/cancel_cast.{type CancelCast}
import genesis_prime/message/cast_ability
import genesis_prime/message/cast_result
import genesis_prime/message/combat_log.{CombatLog}
import genesis_prime/message/combat_log_cc_state.{CombatLogCcState}
import genesis_prime/message/combat_log_entry
import genesis_prime/message/combat_result
import genesis_prime/message/crowd_control_result
import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import genesis_prime/message/damage_type
import genesis_prime/message/float32
import genesis_prime/message/miss_reason
import genesis_prime/message/spell_cast_confirmed.{SpellCastConfirmed}
import genesis_prime/message/spell_cast_refused.{SpellCastRefused}
import genesis_prime/message/spell_damage_description.{
  type SpellDamageDescription, SpellDamageDescription,
}
import genesis_prime/message/spell_effect_bit.{SpellEffectBit}
import genesis_prime/message/spell_effect_damage.{SpellEffectDamage}
import genesis_prime/message/spell_effect_info.{SpellEffectInfo}
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_failed.{SpellFailed}
import genesis_prime/message/spell_finished.{SpellFinished}
import genesis_prime/message/spell_go.{type SpellGo, SpellGo}
import genesis_prime/message/spell_miss.{SpellMiss}
import genesis_prime/message/spell_missed.{type SpellMissed, SpellMissed}
import genesis_prime/message/spell_position.{type SpellPosition, SpellPosition}
import genesis_prime/message/spell_stack_removed.{
  type SpellStackRemoved, SpellStackRemoved,
}
import genesis_prime/message/spell_started.{type SpellStarted, SpellStarted}
import genesis_prime/message/spell_target_info.{
  type SpellTargetInfo, SpellTargetInfo,
}
import genesis_prime/message/spell_targets_removed.{
  type SpellTargetsRemoved, SpellTargetsRemoved,
}
import genesis_prime/message/spell_threshold_closed.{SpellThresholdClosed}
import genesis_prime/message/spell_threshold_index.{SpellThresholdIndex}
import genesis_prime/message/spell_threshold_opened.{SpellThresholdOpened}
import genesis_prime/step.{
  type ConnectionId, type LogLevel, type Now, type TimerId, LogDebug, LogInfo,
  LogWarning, TimerId,
}
import genesis_prime/table/id.{
  type Item2Id, type Spell4BaseId, type Spell4EffectsId, type Spell4Id,
  Spell4EffectsId,
}
import genesis_prime/world_map/map
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/set.{type Set}

/// The messages of a player's casts, which the client sends inside 0x038C
/// (genesis_prime/game/routing says which id is which).
pub type Message {
  /// 0x009A, the press of an ability.
  Pressed
  /// 0x04DB, the key or button of an ability goes down or up under the client's
  /// hold-to-continue-casting setting, which is on by default.
  KeyHeld
  /// 0x0801, the client ends one of its player's casts.
  Cancelled
}

/// The Vital id of Health and of Shield Capacity in `Caster.life_vitals`
/// (`Prerequisite.prerequisiteTypeId.71`: Vital.tbl ids 1 and 3).
pub const health_vital = 1

pub const shield_vital = 3

/// The player that casts, as the connection holds it when it takes an input.
pub type Caster {
  Caster(
    unit_id: Int,
    /// Where the player stands now.
    place: Place,
    /// The abilities the player holds, as Spell4Base ids in bag order
    /// (genesis_prime/game/loadout).
    abilities: List(Spell4BaseId),
    /// The item in the equipped slot 16, when there is one.
    weapon: Option(Item2Id),
    /// The connections whose players see this one.
    audience: Set(ConnectionId),
    /// Whether the player is dead (genesis_prime/game/player_life), which the
    /// client checks a press against (`cast.dead_player`).
    dead: Bool,
    /// The player's class resource (genesis_prime/game/class_resource), which a
    /// press's costs and requirements are checked against and paid from, and whose
    /// slots are the vitals 5 to 11 of a prerequisite.
    resources: Resources,
    /// Whether a creature holds the player on its threat list
    /// (genesis_prime/game/player_life), which a type 28 prerequisite reads.
    in_combat: Bool,
    /// The player's health (Vital 1) and shield (Vital 3), by Vital id, which a
    /// type 71 or 73 prerequisite reads beside the class resource's slots.
    life_vitals: Dict(Int, prerequisite.Vital),
    /// The player's faction and base faction, the two faction fields of its 0x262, which
    /// the type 4 and 250 prerequisites read.
    factions: prerequisite.Factions,
    /// What a damage or heal formula reads of the player: its level and its Assault
    /// and Support Rating (genesis_prime/game/damage).
    stats: damage.Attacker,
    /// The player's health and shield with their maxima, which a heal's formula reads
    /// (genesis_prime/game/damage `value_on_caster`).
    vitals: damage.Vitals,
    /// The player's quest log, which the quest conditions of a prerequisite (types 6,
    /// 68, 43 and 22 to 36) read: the client reads the checking player's own log.
    quests: QuestLog,
    /// The player's race, class, path, gender, level, World and zones, which the
    /// prerequisite types on the player (1, 2, 3, 10, 26, 39, 52 and 109) read.
    player: prerequisite.Player,
  )
}

/// What a caster's spell changes on the caster itself, which starts after the effect's
/// delay: the payload of `CasterChangeStarts` and `Due.ModifierStart`. A change that ends
/// has its end tied to its source alone (`CasterChangeEnds`, `Due.ModifierEnd`), which
/// each owner of a change takes by its source and ignores when it holds none; a shield
/// heal has no end.
pub type CasterChange {
  /// A property modifier (a UnitPropertyModifier or UnitPropertyConversion effect): the
  /// connection applies it to the player's properties (genesis_prime/game/unit_properties `apply`).
  Property(modifier: unit_properties.Modifier)
  /// An absorb pool (an Absorption effect): the connection gives the player's life a pool of
  /// `amount` that takes the damage types of `mask` (bit 1 Physical, 2 Tech, 4 Magic) before
  /// its shield and health (genesis_prime/game/player_life `absorb_started`). The amount is
  /// worked out at the go from the caster's stats, as a heal's is, and the pool lasts until
  /// its end or it is used up (`Spell4Effects.effectType.29`).
  Absorb(amount: Int, mask: Int)
  /// A disguise (a DisguiseOutfit effect): the connection starts it on the player's look,
  /// writes the slots that changed to the player's client and tells its viewers
  /// (genesis_prime/game/look `start`). It ends with the modifiers' own end,
  /// `CasterChangeEnds`.
  Look(disguise: look.Disguise)
  /// A shield heal (a HealShields effect): the connection raises the player's shield by
  /// `amount`, capped at its maximum (genesis_prime/game/player_life `shield_healed`).
  /// The amount is worked out at the go, the amount the go's 0x7f4 shows.
  ShieldHeal(amount: Int)
}

/// What the rule asks the connection to do, in order.
pub type Effect {
  /// Write a message to the caster's client.
  Send(frame: Frame)
  /// Tell the connection of a player who sees the caster the news of a cast.
  Tell(to: ConnectionId, news: News)
  StartTimer(timer: TimerId, after_ms: Int)
  CancelTimer(timer: TimerId)
  Log(level: LogLevel, text: String)
  /// A go is asked: the connection selects its targets, strikes them
  /// (genesis_prime/game/strike) and, when the round closes, answers with `went`.
  /// The go's 0x7f4 waits for that answer.
  Strike(asked: GoAsked)
  /// A cast's costs are taken from the caster's class resource, at its first go, or
  /// at the accept of a spell that goes at once (genesis_prime/game/class_resource
  /// `pay`).
  Pay(payments: List(Payment))
  /// A go's resource gains are given to the caster's class resource
  /// (genesis_prime/game/class_resource `gain`).
  Gain(gains: List(class_resource.Gain))
  /// A change of the caster's spell on the caster itself starts: the connection applies a
  /// property modifier to the player's properties and tells its client and its viewers
  /// the entries that changed (genesis_prime/game/unit_properties `apply`), and raises
  /// the shield for a shield heal (genesis_prime/game/player_life `shield_healed`) and gives
  /// the life an absorb pool for an `Absorb` (genesis_prime/game/player_life `absorb_started`).
  CasterChangeStarts(source: unit_properties.Source, change: CasterChange)
  /// A change of the caster's spell ends, or is told ended for a source the connection may
  /// hold nothing for: it is told by source alone to each owner of a caster change, the
  /// properties (`unit_properties.remove`), the look (`look.end`) and the life
  /// (`player_life.absorb_ended`), and an owner that holds nothing for the source changes
  /// nothing. A source names one cast and one Spell4Effects row, so at most one owner holds it.
  CasterChangeEnds(source: unit_properties.Source)
  /// A property modifier of the caster's spell starts on the creature `unit_id` whose
  /// life the go struck, at the monotonic time `struck_at_ms` the go struck it
  /// (`HitCreature`): the connection tells the creature
  /// (genesis_prime/client_connection `TellTargetChange`), which applies it to its own
  /// properties and tells its viewers the entries that changed. A creature of another
  /// life drops it, and so does one that lies dead or has stood again from its corpse
  /// since the go struck.
  TargetChangeStarts(
    unit_id: Int,
    life: Int,
    struck_at_ms: Int,
    source: unit_properties.Source,
    modifier: unit_properties.Modifier,
  )
  /// A property modifier the caster's spell started on the creature `unit_id` ends: the
  /// node's end, a removal of the cast, its push off or the caster's death. A creature
  /// that holds nothing for the source changes nothing.
  TargetChangeEnds(unit_id: Int, life: Int, source: unit_properties.Source)
  /// The caster entered or left stealth, the last effect of the input that moved it:
  /// the connection writes 0x8f5 to the caster's client and tells each viewer
  /// (`opcode.0x8f5`, genesis_prime/client_connection `Stealth`).
  StealthChanged(stealthed: Bool)
}

/// A go of a live cast that waits for its targets: which cast and phase, the spell,
/// the cast's primary target, which a child cast on a struck unit holds as that
/// unit and any other cast as its caster, and the points the cast spent above its
/// base cost, which choose the effects the go strikes with
/// (genesis_prime/game/spend); none for a cast that spends no more than its cost.
pub type GoAsked {
  GoAsked(
    cast_id: Int,
    phase: Int,
    spell4_id: Spell4Id,
    primary_target: Int,
    spent: Option(Int),
  )
}

/// A unit a go names, from the round that closed (genesis_prime/game/strike).
pub type Struck {
  /// The unit is named in the 0x7f4 with the damage that landed on it, which is
  /// none for a spell that only selects it (Crush's first spell), and the
  /// crowd-control states it took, each listed as an effect of the go with the
  /// instance id its tell gave (genesis_prime/game/strike_tell `Landed`).
  Hit(
    unit_id: Int,
    unit: HitUnit,
    descriptions: List(hit.Description),
    controls: List(strike_tell.ControlLanded),
  )
  /// The unit deflected the strike: an entry of the 0x7fb, no description and no
  /// child (`opcode.0x7fb`).
  Deflected(unit_id: Int)
}

/// What kind of unit a `Hit` names.
pub type HitUnit {
  /// A creature a player's go struck, in the life the go aimed at
  /// (genesis_prime/game/strike `Aimed`), at the monotonic time `struck_at_ms` the go
  /// struck it: a property modifier the go starts on it is told for that life and
  /// that time (`TargetChangeStarts`).
  HitCreature(life: Int, struck_at_ms: Int)
  /// A player a creature's attack struck (genesis_prime/world_map/creature_fight).
  HitPlayer
}

/// A property modifier a cast started on a creature: the creature's unit, the life
/// the go struck, and the modifier's source. Each end of the cast's node on that unit
/// tells it ended (`TargetChangeEnds`).
pub type OnCreature {
  OnCreature(unit_id: Int, life: Int, source: unit_properties.Source)
}

/// Why the client's message is refused: it ends the connection, because the
/// client's own code never sends it.
pub type Refusal {
  /// A body the client's own reader would refuse.
  NotDecoded(undecoded: client_connection.Undecoded)
  /// A 0x9a with the client's cast id 0, which its counter never gives
  /// (`opcode.0x9a`).
  NoClientCastId
  /// A 0x801 whose reason and bit are none the client sends together
  /// (`opcode.0x801`).
  UnknownCancel(reason: Int, bit: Int)
}

/// What a timer of the rule is for, which `State` keeps by the timer's id.
pub type Due {
  /// The go of phase `phase` of the live cast `cast_id`.
  Go(cast_id: Int, phase: Int)
  /// The live channel `cast_id` ends at its channelMaxTime, which can come after
  /// its last pulse.
  Finish(cast_id: Int)
  /// The child cast of `proxy` starts: with the pressed spell as its root and the
  /// spell whose Proxy fired as its parent, which need not be live.
  StartChild(
    root: Spell4Id,
    parent: Spell4Id,
    primary_target: Int,
    proxy: Proxy,
  )
  /// The earliest node of the lingering cast `cast_id` ends: its units' 0x811, or
  /// the finish when no node is left.
  NodesEnd(cast_id: Int)
  /// The crowd-control state `state` the cast `spell4_id` put on the unit `unit_id`
  /// ends on the creature: the caster's combat log gets its end entry.
  StateEnd(spell4_id: Spell4Id, unit_id: Int, state: CrowdControlState)
  /// The change of the caster `source` names starts, after its delay.
  ModifierStart(source: unit_properties.Source, change: CasterChange)
  /// The property modifier `on` names starts on its creature, after its delay, for
  /// the go that struck at `struck_at_ms`.
  TargetModifierStart(
    on: OnCreature,
    modifier: unit_properties.Modifier,
    struck_at_ms: Int,
  )
  /// The property modifier `source` ends, after its duration.
  ModifierEnd(source: unit_properties.Source)
  /// The cooldown effect `source` takes effect, after its delay: it changes the
  /// running cooldowns and, when `kept`, the ones that start while it lasts.
  CooldownModifierStarts(
    source: unit_properties.Source,
    modifier: cooldown.Modifier,
    kept: Bool,
  )
  /// The cooldown effect `source` is no longer kept, after its lifetime.
  CooldownModifierEnds(source: unit_properties.Source)
  /// The held press starts.
  StartHeld
  /// The ability the player holds down casts again: its cooldowns have ended.
  RepeatHeld
  /// The time of the RapidTap threshold of the ability `spell4_id` runs out.
  WindowEnd(spell4_id: Int)
  /// The ChargeRelease threshold of the ability `spell4_id` reaches the charge
  /// level `level`.
  ChargeLevel(spell4_id: Int, level: Int)
}

/// What a press resolved to when it came: the spell it casts, the ability that
/// was pressed, and which stage of the ability's open threshold it casts (none for
/// the ability's own spell).
pub type Resolution {
  Resolution(spell: Spell, ability: Spell, stage: Option(Int))
}

/// What a cast is to its ability's threshold.
type Role {
  /// A child a Proxy started: no threshold is touched.
  Child
  /// The ability's own spell, which opens a threshold when its method has one.
  Base(ability: Spell)
  /// The stage at `index` of the ability's open threshold.
  Stage(ability: Spell, index: Int)
  /// A class's innate passive, which no press made: no threshold is touched, no
  /// global cooldown starts and it is never the current cast.
  Passive
}

/// A cast of the caster that has started and not finished.
pub type Live {
  Live(
    spell: Spell,
    /// The points the cast spent above its base cost, fixed at its accept; none for a
    /// spell with no spend and for a child a Proxy started.
    spent: Option(Int),
    /// The costs the accept checked and the cast's first go pays: empty once paid,
    /// for a cast whose accept paid them (`pays_at_accept`) and for a child.
    reserved: List(Payment),
    /// The spell the player pressed, the root of every child.
    root: Spell4Id,
    /// The spell whose Proxy started this one; none for the pressed spell.
    parent: Option(Spell4Id),
    primary_target: Int,
    /// The connections told of the start, which its go and finish go to.
    audience: Set(ConnectionId),
    /// How many of its gos have been sent.
    gone: Int,
    /// The monotonic time the cast started at, which its time left is counted from.
    started_ms: Int,
    /// The ability whose open threshold this cast is a stage of.
    stage_of: Option(Spell),
    /// Whether this cast's finish closes the ability's threshold: a release, and the
    /// last tap.
    closes_threshold: Bool,
    /// The nodes the cast's gos left on units, by unit id: a later go on the same
    /// unit sets its node again (`opcode.0x7f4.instance_count`).
    nodes: Dict(Int, lasting.Node),
  )
}

/// A cast whose last go has gone and whose nodes still have life left: only its
/// 0x7fe waits until the last node ends, because the client ends no buff on time
/// (`cast.target_node_end`); every other step of its finish has run. `State` keeps it by cast id until a `NodesEnd` timer
/// ends its nodes, a removal takes them off, or the caster dies.
pub type Lingering {
  Lingering(
    spell: Spell,
    /// The connections told of the cast's start, which its 0x811 and 0x7fe go to.
    audience: Set(ConnectionId),
    /// The monotonic time the cast started at: a removal takes the oldest cast
    /// first, and the cast id wraps, so the age is this.
    started_ms: Int,
    /// The unit the cast was aimed at when it started, which its persistence reads.
    primary_target: Int,
    nodes: Dict(Int, lasting.Node),
  )
}

/// An open threshold of one ability: the stage or charge level the next press
/// casts, and the id of the base cast, which the client sends back in a 0x801
/// (`opcode.0x816`).
pub type Threshold {
  Threshold(ability: Spell, index: Int, cast_id: Int)
}

/// A press the client queued within 500 ms of a cooldown's end, or the server
/// queues within 500 ms of the end of the current cast.
pub type Held {
  Held(client_cast_id: Option(Int), resolution: Resolution, until: HeldUntil)
}

/// The ability whose key the player holds down: it casts when the key goes down
/// and again each time its cast has ended and its cooldowns allow, until the key
/// comes up (`cast.hold_repeat`).
pub type Holding {
  Holding(
    ability: Spell,
    /// The timer that waits for the cooldowns to end, when one runs.
    repeat_timer: Option(TimerId),
    /// The cast the hold started last, once it has started one: until that cast is
    /// over the ability is not cast again, and from then on a cooldown is waited
    /// for and no longer refused.
    last_cast: Option(Int),
  )
}

/// What a held press waits for.
pub type HeldUntil {
  /// The cooldown's end, from a timer.
  CooldownEnds
  /// The go or finish that clears the caster's current cast.
  CastClears
}

/// A Proc row a cast holds on the caster, with the times it fired at that are still inside
/// its window (`ProcRow.window_ms`).
type HeldProc {
  HeldProc(row: spell_plan.ProcRow, fires_ms: List(Int))
}

/// What the rule keeps for one player: its cooldowns, its live casts, its open
/// thresholds and what waits on a timer, and the counters its cast ids and timer
/// ids are made from.
pub opaque type State {
  State(
    /// The monotonic time the global cooldown ends at, once one has started. The
    /// monotonic clock can be negative, so 0 never means none.
    global_cooldown_ends_ms: Option(Int),
    /// The running cooldowns of the caster's spells and the cooldown effects kept for
    /// the ones that start later (genesis_prime/game/cooldown). The global cooldown is
    /// the field above: no cooldown effect changes it.
    cooldowns: cooldown.Book,
    casts: Dict(Int, Live),
    /// The casts whose last go has gone and whose nodes still have life left, by
    /// cast id.
    lingering: Dict(Int, Lingering),
    /// The caster's current cast, which a press is refused against (13).
    current: Option(Int),
    /// The open thresholds, by the Spell4 id of the ability.
    thresholds: Dict(Int, Threshold),
    timers: Dict(TimerId, Due),
    held: Option(Held),
    holding: Option(Holding),
    /// How many casts the player has started, which the cast ids are made from.
    presses: Int,
    /// How many timers the rule has started, which the timer ids are made from.
    timers_started: Int,
    /// The Spell4 ids already logged as unbuilt on this connection.
    logged: Set(Int),
    /// The Stealth rows the caster's casts hold on it, by cast id and effect id, each
    /// with whether damage ends it; the caster is stealthed while this is not empty.
    stealth: Dict(unit_properties.Source, spell_plan.Breaks),
    /// The Proc rows the caster's casts hold on it, by cast id and effect id, each with the
    /// monotonic times of its fires still inside its window; a proc leaves where a stealth
    /// source does (`procs_dropped`).
    procs: Dict(unit_properties.Source, HeldProc),
    /// The id of the cast of the player's innate passive, once `passive_started` has
    /// started it: the one cast a death leaves.
    passive: Option(Int),
    /// The persistence columns already logged as not read or not checked on this
    /// connection, by Spell4 id and result (282 or 283): one debug line for each.
    persistence_logged: Set(#(Int, Int)),
    /// The property modifiers the caster's casts started on creatures and have not
    /// ended, by cast id, in the order they started: the node's end by time
    /// (`NodesEnd`), a type 80 removal, a push off by the stack rule, the caster's
    /// death and its leaving each tell `TargetChangeEnds` for those of the cast and
    /// unit they end.
    on_creatures: Dict(Int, List(OnCreature)),
  )
}

/// The timer id the rule's first timer takes; the connection's own are below it.
const first_timer = 1000

/// The queue window: a press with this much of a cooldown left or less is sent
/// by the client and held by the server (`player.abilityQueueMax`, `0x1403b14c0`).
const queue_window_ms = 500

/// The cast ids start here: 2^31, above where a client counter can reach.
const first_cast_id = 2_147_483_648

/// Each unit has this many cast ids: 2^11.
const ids_per_unit = 2048

/// A player that has cast nothing.
pub fn new() -> State {
  State(
    global_cooldown_ends_ms: None,
    cooldowns: cooldown.new(),
    casts: dict.new(),
    lingering: dict.new(),
    current: None,
    thresholds: dict.new(),
    timers: dict.new(),
    held: None,
    holding: None,
    presses: 0,
    timers_started: 0,
    logged: set.new(),
    stealth: dict.new(),
    procs: dict.new(),
    passive: None,
    persistence_logged: set.new(),
    on_creatures: dict.new(),
  )
}

/// Whether the caster is stealthed: some Stealth row of its casts holds. The client
/// is told by 0x8f5 and 0x262's create flag 16, and a type 116 prerequisite reads it.
pub fn stealthed(cast cast: State) -> Bool {
  !dict.is_empty(cast.stealth)
}

/// Whether the timer is one of this rule's, for the connection to hand it to
/// `timer_fired`.
pub fn owns(timer timer: TimerId) -> Bool {
  let TimerId(number) = timer
  number >= first_timer
}

/// The id of the `number`th cast of the unit `unit_id`: 2^31 + unit id x 2^11 +
/// number mod 2^11.
pub fn cast_id(unit_id unit_id: Int, number number: Int) -> Int {
  first_cast_id + unit_id * ids_per_unit + number % ids_per_unit
}

/// The unit a cast id was made for, which is how a viewer finds the casts of a
/// unit it stops showing.
pub fn caster_of(cast_id cast_id: Int) -> Int {
  { cast_id - first_cast_id } / ids_per_unit
}

/// The first id from the `number`th of the unit `unit_id` that none of the live
/// casts `live` holds: the id the rule gives the next cast. A unit holds at most
/// 2^11 ids, and a caster's live casts are far fewer.
pub fn mint(
  unit_id unit_id: Int,
  number number: Int,
  live live: List(Int),
) -> Int {
  mint_from(unit_id:, number:, live:, tried: 0)
}

fn mint_from(
  unit_id unit_id: Int,
  number number: Int,
  live live: List(Int),
  tried tried: Int,
) -> Int {
  let id = cast_id(unit_id:, number:)
  case list.contains(live, id) && tried < ids_per_unit {
    True -> mint_from(unit_id:, number: number + 1, live:, tried: tried + 1)
    False -> id
  }
}

/// The caster's 0x9a, 0x4DB or 0x801, decoded and decided: the new state and what
/// the connection must do, or the refusal that ends the connection. `now` is the
/// time of the input; the plans give each ability's tree.
pub fn take(
  cast cast: State,
  message message: Message,
  body body: BitArray,
  caster caster: Caster,
  plans plans: Plans,
  now now: Now,
) -> Result(#(State, List(Effect)), Refusal) {
  let now_ms = now.monotonic_ms
  case message {
    Pressed -> pressed(cast:, body:, caster:, plans:, now:)
    KeyHeld -> key_held(cast:, body:, caster:, plans:, now:)
    Cancelled ->
      cancelled(cast:, body:, caster:, now:)
      |> result.map(fn(taken) { released(taken:, caster:, now_ms:) })
  }
  |> result.map(fn(taken) { continued(taken:, caster:, now_ms:) })
  |> result.map(fn(taken) {
    settled(cast:, caster:, now:, own: [], step: fn() { taken })
  })
}

/// What an input did, with `StealthChanged` after its own effects when the caster's stealth
/// is not what it was in `cast`, the state before the input: one per input, however many
/// Stealth rows came and went; then the casts of the procs the input's events fire
/// (`procs_fired`): `own` are the input's own events, and the stealth change follows them.
/// `step` is the input's own work.
fn settled(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
  own own: List(spell_plan.Trigger),
  step step: fn() -> #(State, List(Effect)),
) -> #(State, List(Effect)) {
  let #(after, effects) = step()
  let #(after, moved, fired) = case stealthed(cast: after) == stealthed(cast:) {
    True -> {
      let #(after, fired) =
        procs_fired(cast: after, caster:, now:, triggers: own)
      #(after, [], fired)
    }
    False -> {
      let stealthed = stealthed(cast: after)
      let change = case stealthed {
        True -> spell_plan.EnteredStealth
        False -> spell_plan.LeftStealth
      }
      let #(after, fired) =
        procs_fired(
          cast: after,
          caster:,
          now:,
          triggers: list.append(own, [change]),
        )
      #(after, [StealthChanged(stealthed:)], fired)
    }
  }
  #(after, list.flatten([effects, moved, fired]))
}

/// The procs held when an input's own work is done fire for each of the input's events,
/// in the order given (the input's own event, then its stealth change); within an event, in
/// source order, the cast id and then the effect id, which is row order for one holder. A
/// proc whose node the input took off is not held, and one the input applied is.
fn procs_fired(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
  triggers triggers: List(spell_plan.Trigger),
) -> #(State, List(Effect)) {
  use <- bool.guard(when: dict.is_empty(cast.procs), return: #(cast, []))
  list.fold(triggers, #(cast, []), fn(so_far, trigger) {
    let #(cast, effects) = so_far
    dict.to_list(cast.procs)
    |> list.filter(fn(entry) { { entry.1 }.row.trigger == trigger })
    |> list.sort(fn(first, second) {
      int.compare({ first.0 }.cast_id, { second.0 }.cast_id)
      |> order.break_tie(int.compare(
        { first.0 }.effect_id.value,
        { second.0 }.effect_id.value,
      ))
    })
    |> list.fold(#(cast, effects), fn(so_far, entry) {
      let #(cast, effects) = so_far
      let #(cast, more) =
        proc_fired(
          cast:,
          caster:,
          now_ms: now.monotonic_ms,
          source: entry.0,
          held: entry.1,
        )
      #(cast, list.append(effects, more))
    })
  })
}

/// One held proc's trigger happened: it casts its spell at the caster unless it fired
/// `count` times already in the last `window_ms` (a fire exactly `window_ms` ago is
/// outside the window), or the spell's caster condition refuses the caster's life
/// (`Spell4.spell4ConditionsIdCaster`, `cast.dead_player`), which writes a debug line
/// and records no fire. The cast starts as a child of the holder's spell does: the
/// holder's spell is its root and parent, no 0x7fd, and the caster is its primary target.
fn proc_fired(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  source source: unit_properties.Source,
  held held: HeldProc,
) -> #(State, List(Effect)) {
  let row = held.row
  let recent =
    list.filter(held.fires_ms, fn(fired_ms) {
      fired_ms > now_ms - row.window_ms
    })
  use <- bool.guard(when: list.length(recent) >= row.count, return: #(cast, []))
  case holder_of(cast:, cast_id: source.cast_id) {
    Error(Nil) -> #(cast, [
      Log(
        level: LogWarning,
        text: "the Proc effect "
          <> int.to_string(row.effect_id.value)
          <> " is held by the cast "
          <> int.to_string(source.cast_id)
          <> ", which is neither live nor lingering, so it does not fire",
      ),
    ])
    Ok(holder) ->
      proc_cast(cast:, caster:, now_ms:, source:, row:, recent:, holder:)
  }
}

/// The cast of a proc that fires: refused for a caster of a life its spell's caster
/// condition does not allow, else recorded as a fire and started.
fn proc_cast(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  source source: unit_properties.Source,
  row row: spell_plan.ProcRow,
  recent recent: List(Int),
  holder holder: Holder,
) -> #(State, List(Effect)) {
  let spell = row.spell
  use <- bool.guard(
    when: option.is_some(spell_plan.refused_life(spell:, dead: caster.dead)),
    return: #(cast, [
      Log(
        level: LogDebug,
        text: "the Proc effect "
          <> int.to_string(row.effect_id.value)
          <> " of Spell4 "
          <> int.to_string(holder.spell.spell4_id.value)
          <> " does not cast Spell4 "
          <> int.to_string(spell.spell4_id.value)
          <> ", whose caster condition refuses a caster that is "
          <> case caster.dead {
          True -> "dead"
          False -> "alive"
        },
      ),
    ]),
  )
  let cast =
    State(
      ..cast,
      procs: dict.insert(
        cast.procs,
        source,
        HeldProc(row:, fires_ms: [now_ms, ..recent]),
      ),
    )
  start(
    cast:,
    caster:,
    now_ms:,
    spell:,
    root: holder.spell.spell4_id,
    parent: Some(holder.spell.spell4_id),
    primary_target: caster.unit_id,
    client_cast_id: None,
    role: Child,
    spent: None,
    reserved: [],
  )
}

/// The Proc rows of a go that applied, each held by the cast `cast_id` from this go on;
/// a row the cast already holds keeps its fires, as a later go of the same cast is the
/// same node.
fn procs_held(
  cast cast: State,
  cast_id cast_id: Int,
  applied applied: Applied,
) -> #(State, List(Effect)) {
  let #(never, held) =
    list.partition(applied.procs, fn(row) {
      row.trigger == spell_plan.Died && cast.passive != Some(cast_id)
    })
  let procs =
    list.fold(held, cast.procs, fn(procs, row) {
      let source = unit_properties.Source(cast_id:, effect_id: row.effect_id)
      dict.upsert(procs, source, fn(found) {
        case found {
          Some(already) -> already
          None -> HeldProc(row:, fires_ms: [])
        }
      })
    })
  #(
    State(..cast, procs:),
    list.map(never, fn(row) {
      Log(
        level: LogDebug,
        text: "the Proc effect "
          <> int.to_string(row.effect_id.value)
          <> " of kind 0 is held by a cast that is not the innate passive, which a death ends before the proc is matched, so it is not held",
      )
    }),
  )
}

/// A step's result with the held press started when the step cleared the current
/// cast it waited for.
fn released(
  taken taken: #(State, List(Effect)),
  caster caster: Caster,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, effects) = taken
  let caster = after_payments(caster:, effects:)
  case cast.held {
    Some(Held(client_cast_id:, resolution:, until: CastClears)) ->
      case cast.current {
        None -> {
          let #(cast, started) =
            press_of(
              cast: State(..cast, held: None),
              caster:,
              now_ms:,
              client_cast_id:,
              resolution:,
            )
          #(cast, list.append(effects, started))
        }
        Some(_) -> taken
      }
    Some(Held(until: CooldownEnds, ..)) | None -> taken
  }
}

fn pressed(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  plans plans: Plans,
  now now: Now,
) -> Result(#(State, List(Effect)), Refusal) {
  use press <- result.try(
    cast_ability.decode(body)
    |> client_connection.decoded(message_id: cast_ability.message_id)
    |> result.map_error(NotDecoded),
  )
  use <- bool.guard(
    when: press.client_cast_id == 0,
    return: Error(NoClientCastId),
  )
  use <- bool.guard(
    when: press.press == 0,
    return: Ok(
      #(cast, [
        Log(
          level: LogInfo,
          text: "a press with the press bit 0 is a console setting's, which is not built",
        ),
      ]),
    ),
  )
  case ability_at(caster:, plans:, bag_index: press.bag_index) {
    Error(Nil) ->
      Ok(
        #(cast, [
          refused_unknown(client_cast_id: press.client_cast_id, spell4_id: 0),
        ]),
      )
    Ok(ability) ->
      case resolved(cast:, ability:) {
        Error(Nil) ->
          Ok(
            #(cast, [
              refused_unknown(
                client_cast_id: press.client_cast_id,
                spell4_id: ability.spell4_id.value,
              ),
            ]),
          )
        Ok(resolution) ->
          Ok(press_of(
            cast:,
            caster:,
            now_ms: now.monotonic_ms,
            client_cast_id: Some(press.client_cast_id),
            resolution:,
          ))
      }
  }
}

/// The ability the player holds at the bag index, as the plans have it.
fn ability_at(
  caster caster: Caster,
  plans plans: Plans,
  bag_index bag_index: Int,
) -> Result(Spell, Nil) {
  list.drop(caster.abilities, bag_index)
  |> list.first
  |> result.try(fn(base) { spell_plan.in_plans(plans:, base:) })
}

/// The key of an ability goes down (held 1) or up (held 0). The client's reader
/// refuses a body longer or shorter than the message (`opcode.0x4db`), which ends
/// the connection, and a bag index with no ability is answered as a 0x9a's is,
/// with the client cast id 0 the client shows with no pending cast
/// (`cast.hold_stop`).
fn key_held(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  plans plans: Plans,
  now now: Now,
) -> Result(#(State, List(Effect)), Refusal) {
  use change <- result.try(
    ability_hold.decode(body)
    |> client_connection.decoded(message_id: ability_hold.message_id)
    |> result.map_error(NotDecoded),
  )
  let now_ms = now.monotonic_ms
  Ok(
    case
      ability_at(caster:, plans:, bag_index: change.bag_index),
      change.held == 1
    {
      Error(Nil), True -> #(cast, [
        refused_unknown(client_cast_id: 0, spell4_id: 0),
      ])
      Error(Nil), False -> #(cast, [
        Log(
          level: LogDebug,
          text: "the key of the bag index "
            <> int.to_string(change.bag_index)
            <> ", which holds no ability, comes up",
        ),
      ])
      Ok(ability), True -> key_down(cast:, ability:)
      Ok(ability), False -> key_up(cast:, caster:, ability:, now_ms:)
    },
  )
}

/// The ability becomes the one held: a second key down of the ability already held
/// is the same hold, and the newest ability's key replaces the held one, whose
/// cast under way ends by itself (the server's choice: the client sends each key
/// its own key up, and gives no way to hold two). Its first cast is made by
/// `continued`, once the caster is free.
fn key_down(
  cast cast: State,
  ability ability: Spell,
) -> #(State, List(Effect)) {
  case cast.holding {
    Some(Holding(ability: held, ..)) if held.spell4_id == ability.spell4_id -> #(
      cast,
      [],
    )
    Some(_) | None -> {
      let #(cast, cancels) = stop_holding(cast:)
      #(
        State(
          ..cast,
          holding: Some(Holding(ability:, repeat_timer: None, last_cast: None)),
        ),
        cancels,
      )
    }
  }
}

/// The ability's key comes up: its repeats stop, and the cast under way is left to
/// end. A ChargeRelease ability with its threshold open fires its charged stage, as
/// a 0x9a release does.
fn key_up(
  cast cast: State,
  caster caster: Caster,
  ability ability: Spell,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, cancels) = case cast.holding {
    Some(Holding(ability: held, ..)) if held.spell4_id == ability.spell4_id ->
      stop_holding(cast:)
    Some(_) | None -> #(cast, [])
  }
  case
    ability.method == spell_plan.ChargeRelease
    && dict.has_key(cast.thresholds, ability.spell4_id.value)
  {
    False -> #(cast, cancels)
    True ->
      case resolved(cast:, ability:) {
        Error(Nil) -> #(cast, [
          refused_unknown(client_cast_id: 0, spell4_id: ability.spell4_id.value),
          ..cancels
        ])
        Ok(resolution) -> {
          let #(cast, released) =
            press_of(cast:, caster:, now_ms:, client_cast_id: None, resolution:)
          #(cast, list.append(cancels, released))
        }
      }
  }
}

/// No ability is held: the timer that waits to repeat is cancelled.
fn stop_holding(cast cast: State) -> #(State, List(Effect)) {
  case cast.holding {
    None -> #(cast, [])
    Some(Holding(repeat_timer:, ..)) -> {
      let #(cast, cancels) = case repeat_timer {
        Some(timer) -> #(
          State(..cast, timers: dict.delete(cast.timers, timer)),
          [CancelTimer(timer:)],
        )
        None -> #(cast, [])
      }
      #(State(..cast, holding: None), cancels)
    }
  }
}

/// The timer of the held ability's repeat fired: it waits no longer, unless the
/// hold ended or moved on to another timer.
fn repeat_fired(cast cast: State, timer timer: TimerId) -> State {
  State(
    ..cast,
    holding: option.map(cast.holding, fn(holding) {
      case holding.repeat_timer == Some(timer) {
        True -> Holding(..holding, repeat_timer: None)
        False -> holding
      }
    }),
  )
}

/// A step's result with the held ability cast again when the step left nothing in
/// its way: its last cast is over, the caster's current cast is, and no timer waits
/// for a cooldown (`cast.hold_repeat`).
fn continued(
  taken taken: #(State, List(Effect)),
  caster caster: Caster,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, effects) = taken
  let caster = after_payments(caster:, effects:)
  case cast.holding {
    Some(Holding(ability:, repeat_timer: None, last_cast:)) -> {
      let #(cast, more) =
        repeated(cast:, caster:, now_ms:, ability:, last_cast:)
      #(cast, list.append(effects, more))
    }
    Some(Holding(repeat_timer: Some(_), ..)) | None -> taken
  }
}

/// The held ability's next cast: a refusal when no stage is left, nothing while its
/// last cast or the caster's current cast is under way, a timer while a cooldown
/// runs, else the press itself.
fn repeated(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  ability ability: Spell,
  last_cast last_cast: Option(Int),
) -> #(State, List(Effect)) {
  case resolved(cast:, ability:) {
    Error(Nil) -> no_stage_left(cast:, ability:)
    Ok(resolution) ->
      next_cast(cast:, caster:, now_ms:, resolution:, last_cast:)
  }
}

/// A held RapidTap ability whose threshold has no stage at its index: refused, as
/// a 0x9a press is, and the hold ends.
fn no_stage_left(
  cast cast: State,
  ability ability: Spell,
) -> #(State, List(Effect)) {
  let #(cast, cancels) = stop_holding(cast:)
  #(
    cast,
    list.append(cancels, [
      refused_unknown(client_cast_id: 0, spell4_id: ability.spell4_id.value),
    ]),
  )
}

fn next_cast(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  resolution resolution: Resolution,
  last_cast last_cast: Option(Int),
) -> #(State, List(Effect)) {
  let last_cast_is_live =
    option.map(last_cast, dict.has_key(cast.casts, _)) == Some(True)
  let blocked =
    last_cast_is_live
    || casting(cast)
    && !resolution.spell.ignores_casting
    || option.is_some(cast.held)
  let wait_ms = case last_cast {
    Some(_) -> cooldown_wait_ms(cast:, spell: resolution.spell, now_ms:)
    None -> 0
  }
  case blocked, wait_ms > 0 {
    True, _ -> #(cast, [])
    False, True -> repeat_after(cast:, wait_ms:)
    False, False ->
      press_of(cast:, caster:, now_ms:, client_cast_id: None, resolution:)
  }
}

/// How long a held ability waits before it casts again: until the global cooldown
/// its last cast started and the spell's own cooldown have both ended, whether or
/// not the global cooldown would refuse the spell (the server's choice,
/// `cast.hold_repeat`). Every level-1 ability and stage starts a global cooldown or
/// has a cooldown of its own, so a repeat is never at once; a later ability with
/// neither would recast as soon as its cast ended.
fn cooldown_wait_ms(
  cast cast: State,
  spell spell: Spell,
  now_ms now_ms: Int,
) -> Int {
  let #(_, own_left) = cooldown_left_ms(cast:, spell:, now_ms:)
  let global_left =
    option.map(cast.global_cooldown_ends_ms, fn(ends_ms) {
      int.max(0, ends_ms - now_ms)
    })
    |> option.unwrap(0)
  int.max(global_left, own_left)
}

/// The held ability waits `wait_ms` for its cooldowns on a timer of its own.
fn repeat_after(
  cast cast: State,
  wait_ms wait_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, timer, start) = armed(cast:, due: RepeatHeld, after_ms: wait_ms)
  #(
    State(
      ..cast,
      holding: option.map(cast.holding, fn(holding) {
        Holding(..holding, repeat_timer: Some(timer))
      }),
    ),
    [start],
  )
}

/// What a press of the ability casts: through its open threshold the stage at the
/// threshold's index, the ability's own spell at -1, and none past the last stage
/// (`0x1403bfd60`); with no threshold open, the ability's own spell.
fn resolved(
  cast cast: State,
  ability ability: Spell,
) -> Result(Resolution, Nil) {
  case dict.get(cast.thresholds, ability.spell4_id.value) {
    Error(Nil) -> Ok(Resolution(spell: ability, ability:, stage: None))
    Ok(threshold) ->
      spell_plan.stage_at(spell: ability, index: threshold.index)
      |> result.map(fn(spell) {
        Resolution(spell:, ability:, stage: case threshold.index < 0 {
          True -> None
          False -> Some(threshold.index)
        })
      })
  }
}

/// What a press of a spell comes to: the client's refusal, a held press or a
/// cast that starts. A press with no client cast id is a held key's (0x4DB): the
/// server mints the cast id, no 0x7fd is written, a refusal carries the client
/// cast id 0, and a cooldown or a current cast is waited for by the hold itself.
fn press_of(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  client_cast_id client_cast_id: Option(Int),
  resolution resolution: Resolution,
) -> #(State, List(Effect)) {
  let spell = resolution.spell
  let is_release = is_release(resolution:)
  let held = option.is_some(cast.held)
  let refusal = fn(result) {
    refused(
      client_cast_id: option.unwrap(client_cast_id, 0),
      spell4_id: spell.spell4_id.value,
      result:,
    )
  }
  case verdict(cast:, caster:, spell:, now_ms:, is_release:) {
    Accept(paid:) -> {
      let payments = paid.payments
      let cast = case client_cast_id {
        Some(_) -> cast
        None ->
          hold_started(
            cast:,
            ability: resolution.ability,
            cast_id: next_cast_id(cast:, caster:),
          )
      }
      let #(taken, reserved) = case pays_at_accept(spell:) {
        True -> #(paying(payments:), [])
        False -> #([], payments)
      }
      let #(cast, started) = case resolution.stage {
        None ->
          start(
            cast:,
            caster:,
            now_ms:,
            spell:,
            root: resolution.ability.spell4_id,
            parent: None,
            primary_target: caster.unit_id,
            client_cast_id:,
            role: Base(ability: resolution.ability),
            spent: paid.spent,
            reserved:,
          )
        Some(index) ->
          start(
            cast:,
            caster:,
            now_ms:,
            spell:,
            root: resolution.ability.spell4_id,
            parent: Some(resolution.ability.spell4_id),
            primary_target: caster.unit_id,
            client_cast_id:,
            role: Stage(ability: resolution.ability, index:),
            spent: paid.spent,
            reserved:,
          )
      }
      #(cast, list.append(taken, started))
    }
    Refuse(result:) ->
      refused_hold(
        cast:,
        client_cast_id:,
        ability: resolution.ability,
        effects: [
          refusal(result),
        ],
      )
    NotBuilt(result:, why:) ->
      case set.contains(cast.logged, spell.spell4_id.value) {
        True ->
          refused_hold(
            cast:,
            client_cast_id:,
            ability: resolution.ability,
            effects: [refusal(result)],
          )
        False ->
          refused_hold(
            cast: State(
              ..cast,
              logged: set.insert(cast.logged, spell.spell4_id.value),
            ),
            client_cast_id:,
            ability: resolution.ability,
            effects: [
              Log(
                level: LogWarning,
                text: "the ability with Spell4 "
                  <> int.to_string(spell.spell4_id.value)
                  <> " "
                  <> why
                  <> ": it is refused with "
                  <> int.to_string(cast_result.to_value(result)),
              ),
              refusal(result),
            ],
          )
      }
    Hold(..) | HoldForCast if is_release && held -> #(cast, [
      refusal(cast_result.SpellAlreadyCasting),
    ])
    Hold(wait_ms:) ->
      case client_cast_id, is_release {
        None, False -> repeat_after(cast:, wait_ms:)
        Some(_), _ | None, True -> {
          let #(cast, _, start) =
            armed(cast:, due: StartHeld, after_ms: wait_ms)
          #(
            State(
              ..cast,
              held: Some(Held(client_cast_id:, resolution:, until: CooldownEnds)),
            ),
            [start],
          )
        }
      }
    HoldForCast ->
      case client_cast_id, is_release {
        None, False -> #(cast, [])
        Some(_), _ | None, True -> #(
          State(
            ..cast,
            held: Some(Held(client_cast_id:, resolution:, until: CastClears)),
          ),
          [],
        )
      }
  }
}

/// The ability's hold has started the cast `cast_id`, so its cooldowns are waited
/// for from now on and no longer refused.
fn hold_started(
  cast cast: State,
  ability ability: Spell,
  cast_id cast_id: Int,
) -> State {
  case cast.holding {
    Some(Holding(ability: held, ..) as holding)
      if held.spell4_id == ability.spell4_id
    ->
      State(..cast, holding: Some(Holding(..holding, last_cast: Some(cast_id))))
    Some(_) | None -> cast
  }
}

/// A refusal of a press written; a refused held key stops its hold, which the
/// client does not know (it shows the failure and goes on holding).
fn refused_hold(
  cast cast: State,
  client_cast_id client_cast_id: Option(Int),
  ability ability: Spell,
  effects effects: List(Effect),
) -> #(State, List(Effect)) {
  case client_cast_id, cast.holding {
    None, Some(Holding(ability: held, ..))
      if held.spell4_id == ability.spell4_id
    -> {
      let #(cast, cancels) = stop_holding(cast:)
      #(cast, list.append(cancels, effects))
    }
    Some(_), _ | None, Some(_) | None, None -> #(cast, effects)
  }
}

/// Whether the press is the release of a ChargeRelease threshold: the client has
/// resolved it through the open threshold before any caster check, so a held press
/// does not refuse it (`0x1403bfd60`).
fn is_release(resolution resolution: Resolution) -> Bool {
  case resolution.stage {
    Some(_) -> resolution.ability.method == spell_plan.ChargeRelease
    None -> False
  }
}

/// Spell4CastResult 58, Caster_MustBeDead: a living caster's press of a spell
/// whose caster row asks for a dead one (`Spell4.spell4ConditionsIdCaster`).
const caster_must_be_dead = 58

/// What the client's checks make of a press, in its order: the caster's death, a
/// press held already and the method, then CheckCastCaster's own in its order
/// (`0x1403afb10.order`): the current cast, the cooldowns (a press within the queue
/// window passing as the client's 317 does), the caster requirements (waived by the
/// spell's waiver), the innate costs, the weapon and, last, the spell's own cast conditions
/// (`0x1403ace00`).
type Verdict {
  /// The press is accepted, and its cast pays these costs at its first go (at the
  /// accept when it goes at once).
  Accept(paid: Paid)
  Refuse(result: cast_result.CastResult)
  /// The press is within the queue window of a cooldown's end; its costs are
  /// checked again and paid when it starts.
  Hold(wait_ms: Int)
  /// The caster's current cast has 500 ms or less left: the press waits for the go
  /// or finish that clears it, which is the server's choice (`cast.press_queue`).
  HoldForCast
  /// The spell waits for a later step: its method is not built, its cost needs a
  /// vital the server does not hold, or a cast condition or waiver is of a type the
  /// server does not read. It is refused, and logged once.
  NotBuilt(result: cast_result.CastResult, why: String)
}

fn verdict(
  cast cast: State,
  caster caster: Caster,
  spell spell: Spell,
  now_ms now_ms: Int,
  is_release is_release: Bool,
) -> Verdict {
  let refused_life = spell_plan.refused_life(spell:, dead: caster.dead)
  use <- bool.guard(
    when: refused_life == Some(spell_plan.RefusesDead),
    return: Refuse(result: cast_result.CasterCannotBeDead),
  )
  use <- bool.guard(
    when: refused_life == Some(spell_plan.RefusesLiving),
    return: Refuse(result: cast_result.from_value(caster_must_be_dead)),
  )
  use <- bool.guard(
    when: option.is_some(cast.held) && !is_release,
    return: Refuse(result: cast_result.SpellAlreadyCasting),
  )
  use <- bool.guard(
    when: !is_built(spell.method),
    return: NotBuilt(
      result: cast_result.IllegalSpellCast,
      why: "is not cast by a method that is built",
    ),
  )
  use <- bool.guard(
    when: casting(cast) && !spell.ignores_casting,
    return: case time_left_of_current_cast(cast:, now_ms:) {
      Some(left_ms) if left_ms <= queue_window_ms -> HoldForCast
      Some(_) | None -> Refuse(result: cast_result.SpellAlreadyCasting)
    },
  )
  let #(global_left, own_left) = cooldown_left_ms(cast:, spell:, now_ms:)
  use <- bool.guard(
    when: global_left > queue_window_ms,
    return: Refuse(result: cast_result.SpellGlobalCooldown),
  )
  use <- bool.guard(
    when: own_left > queue_window_ms,
    return: Refuse(result: cast_result.SpellCooldown),
  )
  case
    requirement_refusal(cast:, caster:, spell:),
    costs_paid(
      costs: spell.costs,
      resources: unreserved(cast:, resources: caster.resources),
    )
  {
    Some(refusal), _ -> refusal
    None, Error(Unpaid(result:)) ->
      Refuse(result: cast_result.from_value(result))
    None, Error(Unheld(result:)) ->
      NotBuilt(
        result: cast_result.from_value(result),
        why: "has an innate cost of a vital the server does not hold",
      )
    None, Error(UnreadSpend(result:, emm_id:)) ->
      NotBuilt(
        result: cast_result.from_value(result),
        why: "has an innate cost spent by the EMM id "
          <> int.to_string(emm_id)
          <> ", which the server does not read",
      )
    None, Ok(paid) ->
      case lacks_the_weapon(spell:, caster:), int.max(global_left, own_left) {
        True, _ -> Refuse(result: cast_result.WeaponSlot)
        False, 0 -> cast_conditions(cast:, caster:, spell:, paid:)
        False, wait_ms -> Hold(wait_ms:)
      }
  }
}

/// What the spell's caster requirements make of the press: the refusal for the first the
/// caster fails and its waiver does not pass (`0x1403b1780`), none when each is met or
/// waived. A waiver the server cannot read refuses with the requirement's result, as
/// not built (the server's choice, as for a cost in a vital it does not hold).
fn requirement_refusal(
  cast cast: State,
  caster caster: Caster,
  spell spell: Spell,
) -> Option(Verdict) {
  list.find_map(spell.requirements, fn(requirement) {
    case meets(requirement:, resources: caster.resources) {
      True -> Error(Nil)
      False ->
        case waiver_verdict(cast:, caster:, spell:) {
          prerequisite.Passes -> Error(Nil)
          prerequisite.Fails ->
            Ok(Refuse(result: cast_result.from_value(requirement.result)))
          prerequisite.NotRead(prerequisite_type:) ->
            Ok(NotBuilt(
              result: cast_result.from_value(requirement.result),
              why: "has a caster requirement whose waiver is a condition of the PrerequisiteType "
                <> int.to_string(prerequisite_type)
                <> ", which the server does not read",
            ))
        }
    }
  })
  |> option.from_result
}

/// What the spell's waiver makes of a failed requirement: the waiver's prerequisite
/// checked against the caster, and a spell that has none fails (`0x1403b1780`).
fn waiver_verdict(
  cast cast: State,
  caster caster: Caster,
  spell spell: Spell,
) -> prerequisite.Verdict {
  case spell.caster_cast {
    spell_plan.RequirementWaiver(prerequisite: waiver) ->
      prerequisite.check(
        prerequisite: waiver,
        subject: subject_of(cast:, caster:),
      )
    spell_plan.CastGate(..) | spell_plan.NoCasterCast -> prerequisite.Fails
  }
}

/// The press that passed every other check, now against the spell's own cast
/// conditions in the client's order: CasterCast, then TargetCast (`0x1403ace00`). The
/// caster is both units of each check: the server reads no target, and the client makes
/// the caster the target of every spell it presses (the cast module's doc, "The target").
/// A condition the server cannot read, a type it does not read or a roll (a press draws
/// none), refuses with the check's result as not built.
fn cast_conditions(
  cast cast: State,
  caster caster: Caster,
  spell spell: Spell,
  paid paid: Paid,
) -> Verdict {
  let caster_gate = case spell.caster_cast {
    spell_plan.CastGate(prerequisite: gate) -> Some(gate)
    spell_plan.RequirementWaiver(..) | spell_plan.NoCasterCast -> None
  }
  use <- bool.guard(
    when: option.is_none(caster_gate) && option.is_none(spell.target_cast),
    return: Accept(paid:),
  )
  let subject = subject_of(cast:, caster:)
  case
    condition_verdict(
      gate: caster_gate,
      subject:,
      result: cast_result.PrereqCasterCast,
    )
  {
    Some(refusal) -> refusal
    None ->
      case
        condition_verdict(
          gate: spell.target_cast,
          subject:,
          result: cast_result.PrereqTargetCast,
        )
      {
        Some(refusal) -> refusal
        None -> Accept(paid:)
      }
  }
}

/// What a Prerequisite column of the spell makes of the subject; a spell with none passes.
fn column_verdict(
  gate gate: Option(prerequisite.Prerequisite),
  subject subject: prerequisite.Subject,
) -> prerequisite.Verdict {
  case gate {
    None -> prerequisite.Passes
    Some(gate) -> prerequisite.check(prerequisite: gate, subject:)
  }
}

/// The refusal a cast condition gives when it fails or cannot be read, none when it
/// passes or the spell has none.
fn condition_verdict(
  gate gate: Option(prerequisite.Prerequisite),
  subject subject: prerequisite.Subject,
  result result: cast_result.CastResult,
) -> Option(Verdict) {
  case column_verdict(gate:, subject:) {
    prerequisite.Passes -> None
    prerequisite.Fails -> Some(Refuse(result:))
    prerequisite.NotRead(prerequisite_type:) ->
      Some(NotBuilt(
        result:,
        why: "has a cast condition of the PrerequisiteType "
          <> int.to_string(prerequisite_type)
          <> ", which the server does not read",
      ))
  }
}

/// Whether the caster's slot meets the requirement: its amount, or its percentage
/// of its maximum, compared with the value by the eval (`0x1403b1780`,
/// `0x1407a1750`). The client divides by a maximum of 0 as a float: a slot above 0
/// is then infinitely many percent, and one at 0 is no number, which every
/// comparison fails.
fn meets(
  requirement requirement: spell_plan.Requirement,
  resources resources: Resources,
) -> Bool {
  let current = class_resource.value(resources:, slot: requirement.slot)
  let max = class_resource.max(resources:, slot: requirement.slot)
  let value = int.to_float(requirement.value)
  case requirement.measure, max == 0.0 {
    spell_plan.Amount, _ ->
      compares(comparison: requirement.comparison, current:, value:)
    spell_plan.PercentOfMax, False ->
      compares(
        comparison: requirement.comparison,
        current: current *. 100.0 /. max,
        value:,
      )
    spell_plan.PercentOfMax, True ->
      current >. 0.0
      && case requirement.comparison {
        spell_plan.Greater | spell_plan.AtLeast -> True
        spell_plan.Equal
        | spell_plan.Less
        | spell_plan.AtMost
        | spell_plan.NeverPasses(..) -> False
      }
  }
}

/// CompareByEval (`0x1407a1750`): the current value against the requirement's.
fn compares(
  comparison comparison: spell_plan.Comparison,
  current current: Float,
  value value: Float,
) -> Bool {
  case comparison {
    spell_plan.Equal -> current == value
    spell_plan.Greater -> current >. value
    spell_plan.AtLeast -> current >=. value
    spell_plan.Less -> current <. value
    spell_plan.AtMost -> current <=. value
    spell_plan.NeverPasses(..) -> False
  }
}

/// Why a press's costs are not paid.
type CostRefusal {
  /// The caster's slot holds too little: refused with the cost's result.
  Unpaid(result: Int)
  /// The cost is in a vital the server does not hold.
  Unheld(result: Int)
  /// The cost's EMM id is one the server does not read (genesis_prime/game/spend).
  UnreadSpend(result: Int, emm_id: Int)
}

/// What an accepted press pays and the points it spent above its base cost, which are
/// the cast's n; none when no cost of the spell spends every point held.
type Paid {
  Paid(payments: List(Payment), spent: Option(Int))
}

/// The spell's costs checked in order against the caster's resources, each against
/// the slots as they stand before the press, as the client checks them
/// (`0x1403b1de0`): the first refusal, or what the press pays. A cost that spends
/// every point held is checked against its base amount alone (`0x1403b3320`) and
/// pays every whole point the slot holds; the points above the base are the spend,
/// the first such cost's when the spell has several.
fn costs_paid(
  costs costs: List(spell_plan.Cost),
  resources resources: Resources,
) -> Result(Paid, CostRefusal) {
  list.try_fold(costs, Paid(payments: [], spent: None), fn(paid, cost) {
    cost_taken(paid:, cost:, resources:)
  })
  |> result.map(fn(paid) { Paid(..paid, payments: list.reverse(paid.payments)) })
}

/// One cost checked and added to what the press pays.
fn cost_taken(
  paid paid: Paid,
  cost cost: spell_plan.Cost,
  resources resources: Resources,
) -> Result(Paid, CostRefusal) {
  case cost {
    spell_plan.UnheldCost(result:) -> Error(Unheld(result:))
    spell_plan.UnreadSpendCost(result:, emm_id:) ->
      Error(UnreadSpend(result:, emm_id:))
    spell_plan.SlotCost(slot:, amount:, result:) ->
      case whole_points(resources:, slot:) < int.absolute_value(amount) {
        True -> Error(Unpaid(result:))
        False -> Ok(adding(paid:, payment: Payment(slot:, amount:)))
      }
    spell_plan.SpendAllCost(slot:, amount:, result:) ->
      spend_all(paid:, slot:, amount:, result:, resources:)
    spell_plan.ClassVitalCost(slots: [], ..) -> Ok(paid)
    spell_plan.ClassVitalCost(slots:, amount:, result:) ->
      case
        list.find(slots, fn(slot) {
          let left =
            class_resource.value(resources:, slot:) -. int.to_float(amount)
          left >=. 0.0 && left <=. class_resource.max(resources:, slot:)
        })
      {
        Ok(slot) -> Ok(adding(paid:, payment: Payment(slot:, amount:)))
        Error(Nil) -> Error(Unpaid(result:))
      }
  }
}

/// A cost that spends every point held: refused when the slot holds less than the
/// base amount, else it takes every whole point and the points above the base are
/// the spend, kept from the first such cost.
fn spend_all(
  paid paid: Paid,
  slot slot: Int,
  amount amount: Int,
  result result: Int,
  resources resources: Resources,
) -> Result(Paid, CostRefusal) {
  let held = whole_points(resources:, slot:)
  let base = int.absolute_value(amount)
  use <- bool.guard(when: held < base, return: Error(Unpaid(result:)))
  let paid = adding(paid:, payment: Payment(slot:, amount: held))
  Ok(Paid(..paid, spent: option.or(paid.spent, Some(held - base))))
}

/// The payment added to what the press pays, newest first.
fn adding(paid paid: Paid, payment payment: Payment) -> Paid {
  Paid(..paid, payments: [payment, ..paid.payments])
}

/// The whole points the slot holds, as an absolute value (`0x1403b3320` reads a slot
/// as a whole number).
fn whole_points(resources resources: Resources, slot slot: Int) -> Int {
  float.truncate(class_resource.value(resources:, slot:))
  |> int.absolute_value
}

/// The effect that pays these costs, none for no costs.
fn paying(payments payments: List(Payment)) -> List(Effect) {
  case payments {
    [] -> []
    [_, ..] -> [Pay(payments:)]
  }
}

/// Whether a press's costs are paid at its accept: a cast whose first go is at once
/// and a cast with no go of its own (a charge held until its release) have no later
/// moment to pay at. Any other cast reserves its costs at the accept and pays them
/// at its first go.
fn pays_at_accept(spell spell: Spell) -> Bool {
  case spell_plan.go_times_ms(spell:) {
    [] | [0, ..] -> True
    [_, ..] -> False
  }
}

/// The caster's resources less what the live casts have reserved: what a press's
/// costs are checked against, so a second press cannot be accepted on points a first
/// cast will pay at its go.
fn unreserved(cast cast: State, resources resources: Resources) -> Resources {
  class_resource.paid(
    resources:,
    payments: list.flat_map(dict.values(cast.casts), fn(live) { live.reserved }),
  )
}

/// The caster with the payments and gains among the effects taken into its
/// resources, so a second press of the same step, such as a held press a go
/// releases, is checked against what the first left.
pub fn after_payments(
  caster caster: Caster,
  effects effects: List(Effect),
) -> Caster {
  Caster(
    ..caster,
    resources: list.fold(effects, caster.resources, fn(resources, effect) {
      case effect {
        Pay(payments:) -> class_resource.paid(resources:, payments:)
        Gain(gains:) -> class_resource.gain(resources:, gains:).0
        Send(..)
        | Tell(..)
        | StartTimer(..)
        | CancelTimer(..)
        | Log(..)
        | Strike(..)
        | CasterChangeStarts(..)
        | CasterChangeEnds(..)
        | TargetChangeStarts(..)
        | TargetChangeEnds(..)
        | StealthChanged(..) -> resources
      }
    }),
  )
}

/// What is left of the global cooldown, when it refuses the spell, and of the
/// spell's own cooldown, in milliseconds.
fn cooldown_left_ms(
  cast cast: State,
  spell spell: Spell,
  now_ms now_ms: Int,
) -> #(Int, Int) {
  let global_left = case
    spell.global_cooldown.refused_while_running,
    option.map(cast.global_cooldown_ends_ms, fn(ends_ms) {
      int.max(0, ends_ms - now_ms)
    })
  {
    True, Some(left_ms) -> left_ms
    True, None | False, Some(_) | False, None -> 0
  }
  let own_left =
    cooldown.left_ms(book: cast.cooldowns, spell4_id: spell.spell4_id, now_ms:)
  #(global_left, own_left)
}

/// The methods the rule casts; a spell of any other is refused 285.
fn is_built(method: spell_plan.CastMethod) -> Bool {
  case method {
    spell_plan.Normal
    | spell_plan.Multiphase
    | spell_plan.Channeled
    | spell_plan.RapidTap
    | spell_plan.ChargeRelease -> True
    spell_plan.PressHold
    | spell_plan.ChanneledField
    | spell_plan.ClientSideInteraction
    | spell_plan.Transactional
    | spell_plan.OtherMethod(..) -> False
  }
}

fn lacks_the_weapon(spell spell: Spell, caster caster: Caster) -> Bool {
  case spell.weapon {
    spell_plan.PrimaryWeapon -> option.is_none(caster.weapon)
    spell_plan.Refused -> True
    spell_plan.NoWeaponNeeded | spell_plan.OtherWeaponSlot(..) -> False
  }
}

/// Whether the caster's current cast is live and blocks a press: a live cast of a
/// spell that leaves the caster free never does (`0x1403afb10`,
/// `Spell4.propertyFlags`).
fn casting(cast: State) -> Bool {
  case cast.current {
    None -> False
    Some(cast_id) ->
      case dict.get(cast.casts, cast_id) {
        Ok(live) -> !live.spell.free_while_live
        Error(Nil) -> False
      }
  }
}

/// The time the caster's current cast has left, in milliseconds, from its start
/// and its duration (`cast.press_queue`); none when it has no end of its own,
/// such as a charge held until its release.
fn time_left_of_current_cast(
  cast cast: State,
  now_ms now_ms: Int,
) -> Option(Int) {
  option.then(cast.current, fn(cast_id) {
    dict.get(cast.casts, cast_id) |> option.from_result
  })
  |> option.then(fn(live) {
    spell_plan.duration_ms(spell: live.spell)
    |> option.map(fn(duration_ms) {
      int.max(0, live.started_ms + duration_ms - now_ms)
    })
  })
}

fn cancelled(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  now now: Now,
) -> Result(#(State, List(Effect)), Refusal) {
  use cancel <- result.try(
    cancel_cast.decode(body)
    |> client_connection.decoded(message_id: cancel_cast.message_id)
    |> result.map_error(NotDecoded),
  )
  let reason = cast_result.to_value(cancel.reason)
  use <- bool.guard(
    when: !{
      { reason == 6 || reason == 11 }
      && cancel.field_3 == 1
      || reason == 0
      && cancel.field_3 == 0
    },
    return: Error(UnknownCancel(reason:, bit: cancel.field_3)),
  )
  // A cancel is the player's intent to stop: the cast it names ends the hold that
  // started it (the server's choice), so nothing restarts or fires after it.
  let #(cast, stopped) = stop_holding_cast(cast:, cast_id: cancel.cast_id)
  let #(cast, effects) =
    cancelling(cast:, cancel:, caster:, now_ms: now.monotonic_ms)
  Ok(#(cast, list.append(stopped, effects)))
}

/// The hold whose last cast is `cast_id` ends.
fn stop_holding_cast(
  cast cast: State,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  case cast.holding {
    Some(Holding(last_cast: Some(last), ..)) if last == cast_id ->
      stop_holding(cast:)
    Some(_) | None -> #(cast, [])
  }
}

/// What a cancel the client may send ends: an open charge with its threshold, or
/// a live cast.
fn cancelling(
  cast cast: State,
  cancel cancel: CancelCast,
  caster caster: Caster,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let reason = cast_result.to_value(cancel.reason)
  case reason == 0, open_charge_of(cast:, cast_id: cancel.cast_id) {
    True, None -> #(State(..cast, current: None), [
      Log(
        level: LogDebug,
        text: "the client ended the threshold of the cast "
          <> int.to_string(cancel.cast_id)
          <> ", which is not open",
      ),
    ])
    True, Some(threshold) | False, Some(threshold) ->
      // The client clears the player's current cast before it sends, whatever cast
      // that is (`cast.current_cast`); the base cast of the charge ends with the
      // threshold.
      close_threshold(
        cast: State(..cast, current: None),
        ability: threshold.ability,
        now_ms:,
      )
    False, None -> {
      let cast = State(..cast, current: None)
      case dict.get(cast.casts, cancel.cast_id) {
        Error(Nil) -> #(cast, [
          Log(
            level: LogDebug,
            text: "the client ended the cast "
              <> int.to_string(cancel.cast_id)
              <> ", which is not live",
          ),
        ])
        Ok(live) ->
          end_live_cast(cast:, caster:, cast_id: cancel.cast_id, live:, now_ms:)
      }
    }
  }
}

/// A live cast the client cancelled stops: its waiting go and finish timers are
/// cancelled and it ends as after its last go (`finish_or_linger`): a cancel ends no
/// buff, so a cast that holds a node with life left lingers. A cast of
/// `EndsStealthAfterLastGo` that stops after at least one go and before its last ends
/// the other casts' stealth as it stops, since the goes that ran applied their effects;
/// one that stops before any go keeps it (`Spell4.spellCastStealthChange.break`; the
/// server's choice for the stop, the client giving no case). A death or leaving drops
/// every source already, so a 0x801 is the only stop that reaches this.
fn end_live_cast(
  cast cast: State,
  caster caster: Caster,
  cast_id cast_id: Int,
  live live: Live,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, cancels) = stop_pending(cast:, cast_id:)
  let #(cast, finished) = finish_or_linger(cast:, cast_id:, live:, now_ms:)
  let stopped_early =
    live.spell.stealth_change == spell_plan.EndsStealthAfterLastGo
    && live.gone > 0
    && live.gone < spell_plan.go_count(spell: live.spell)
  let #(cast, broken) = case stopped_early {
    True ->
      stealth_ended(
        cast:,
        caster:,
        sources: other_casts_sources(cast:, cast_id:),
        now_ms:,
      )
    False -> #(cast, [])
  }
  #(cast, list.flatten([cancels, finished, broken]))
}

/// The stealth sources held by casts other than `cast_id`: a cast's own sources are
/// never ended by its own stealth change.
fn other_casts_sources(
  cast cast: State,
  cast_id cast_id: Int,
) -> List(unit_properties.Source) {
  list.filter(dict.keys(cast.stealth), fn(source) { source.cast_id != cast_id })
}

/// The go and finish timers a live cast waits on, cancelled.
fn stop_pending(
  cast cast: State,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  cancel_timers(cast:, matching: fn(due) {
    case due {
      Go(cast_id: waiting, ..) | Finish(cast_id: waiting) -> waiting == cast_id
      StartChild(..)
      | NodesEnd(..)
      | StateEnd(..)
      | ModifierStart(..)
      | TargetModifierStart(..)
      | ModifierEnd(..)
      | CooldownModifierStarts(..)
      | CooldownModifierEnds(..)
      | StartHeld
      | RepeatHeld
      | WindowEnd(..)
      | ChargeLevel(..) -> False
    }
  })
}

/// Every timer whose purpose `matching` accepts is forgotten and cancelled.
fn cancel_timers(
  cast cast: State,
  matching matching: fn(Due) -> Bool,
) -> #(State, List(Effect)) {
  let waiting = dict.filter(cast.timers, fn(_, due) { matching(due) })
  #(
    State(..cast, timers: dict.drop(cast.timers, dict.keys(waiting))),
    list.map(dict.keys(waiting), fn(timer) { CancelTimer(timer:) }),
  )
}

/// The open threshold whose base cast is `cast_id`: the 32-bit value the 0x816
/// carried, which the client names in a 0x801 (`opcode.0x816`).
fn open_charge_of(cast cast: State, cast_id cast_id: Int) -> Option(Threshold) {
  dict.values(cast.thresholds)
  |> list.find(fn(threshold) {
    threshold.cast_id == cast_id
    && threshold.ability.method == spell_plan.ChargeRelease
  })
  |> option.from_result
}

/// A timer of the rule fired: a go, a finish, a child cast, the held press or a
/// threshold's time.
pub fn timer_fired(
  cast cast: State,
  timer timer: TimerId,
  caster caster: Caster,
  now now: Now,
) -> #(State, List(Effect)) {
  use <- settled(cast:, caster:, now:, own: [])
  released(
    taken: fire(cast:, timer:, caster:, now:),
    caster:,
    now_ms: now.monotonic_ms,
  )
  |> continued(caster:, now_ms: now.monotonic_ms)
}

fn fire(
  cast cast: State,
  timer timer: TimerId,
  caster caster: Caster,
  now now: Now,
) -> #(State, List(Effect)) {
  case dict.get(cast.timers, timer) {
    Error(Nil) -> #(cast, [])
    Ok(due) -> {
      let cast = State(..cast, timers: dict.delete(cast.timers, timer))
      let now_ms = now.monotonic_ms
      case due {
        Go(cast_id:, phase:) -> asked(cast:, cast_id:, phase:)
        Finish(cast_id:) ->
          case dict.get(cast.casts, cast_id) {
            Error(Nil) -> #(cast, [])
            Ok(live) -> finish_or_linger(cast:, cast_id:, live:, now_ms:)
          }
        StartChild(root:, parent:, proxy:, primary_target:) ->
          start(
            cast:,
            caster:,
            now_ms:,
            spell: proxy.spell,
            root:,
            parent: Some(parent),
            primary_target:,
            client_cast_id: None,
            role: Child,
            spent: None,
            reserved: [],
          )
        NodesEnd(cast_id:) -> nodes_ended(cast:, cast_id:, now_ms:)
        StateEnd(spell4_id:, unit_id:, state:) -> #(cast, [
          Send(frame: control_logged_frame(
            caster_unit_id: caster.unit_id,
            unit_id:,
            spell4_id:,
            state:,
            removed: True,
          )),
        ])
        ModifierStart(source:, change:) -> #(cast, [
          CasterChangeStarts(source:, change:),
        ])
        ModifierEnd(source:) -> #(cast, [CasterChangeEnds(source:)])
        TargetModifierStart(on:, modifier:, struck_at_ms:) ->
          target_modifier_started(cast:, on:, modifier:, struck_at_ms:)
        CooldownModifierStarts(source:, modifier:, kept:) ->
          cooldown_applied(cast:, source:, modifier:, kept:, now_ms:)
        CooldownModifierEnds(source:) -> #(
          State(..cast, cooldowns: cooldown.drop(book: cast.cooldowns, source:)),
          [],
        )
        RepeatHeld -> #(repeat_fired(cast:, timer:), [])
        StartHeld ->
          case cast.held {
            None -> #(cast, [])
            Some(Held(client_cast_id:, resolution:, ..)) ->
              press_of(
                cast: State(..cast, held: None),
                caster:,
                now_ms:,
                client_cast_id:,
                resolution:,
              )
          }
        WindowEnd(spell4_id:) -> window_ended(cast:, spell4_id:, now_ms:)
        ChargeLevel(spell4_id:, level:) ->
          charge_level_reached(cast:, spell4_id:, level:)
      }
    }
  }
}

/// The delay of a property modifier on a creature ran out: it starts on the creature
/// (`TargetChangeStarts`) and the cast keeps it in `on_creatures` until an end of its
/// node; a cast that has ended since starts nothing.
fn target_modifier_started(
  cast cast: State,
  on on: OnCreature,
  modifier modifier: unit_properties.Modifier,
  struck_at_ms struck_at_ms: Int,
) -> #(State, List(Effect)) {
  let cast_id = on.source.cast_id
  let held = case holder_of(cast:, cast_id:) {
    Ok(holder) -> dict.has_key(holder.nodes, on.unit_id)
    Error(Nil) -> False
  }
  use <- bool.guard(when: !held, return: #(cast, []))
  // A later go of the cast strikes the same creature again: its start replaces the
  // earlier one, which the creature replaces by source too.
  let started =
    dict.get(cast.on_creatures, cast_id)
    |> result.unwrap([])
    |> list.filter(fn(kept) {
      kept.unit_id != on.unit_id || kept.source != on.source
    })
  #(
    State(
      ..cast,
      on_creatures: dict.insert(
        cast.on_creatures,
        cast_id,
        list.append(started, [on]),
      ),
    ),
    [
      TargetChangeStarts(
        unit_id: on.unit_id,
        life: on.life,
        struck_at_ms:,
        source: on.source,
        modifier:,
      ),
    ],
  )
}

/// The property modifiers the cast `cast_id` holds on the creatures `ending` names end:
/// each that started is told ended once and forgotten, and each that still waits for
/// its delay has its timer cancelled and is told nothing. A modifier already ended is
/// not told again.
fn creature_modifiers_ended(
  cast cast: State,
  cast_id cast_id: Int,
  unit_ids unit_ids: List(Int),
) -> #(State, List(Effect)) {
  creatures_ended(cast:, cast_id:, ending: list.contains(unit_ids, _))
}

/// Every property modifier the cast `cast_id` holds on a creature ends, as a persistence
/// that stops holding destroys all its nodes.
fn creature_modifiers_all_ended(
  cast cast: State,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  creatures_ended(cast:, cast_id:, ending: fn(_) { True })
}

fn creatures_ended(
  cast cast: State,
  cast_id cast_id: Int,
  ending ending: fn(Int) -> Bool,
) -> #(State, List(Effect)) {
  let #(cast, cancels) =
    cancel_timers(cast:, matching: fn(due) {
      case target_start_of(due:) {
        Ok(waiting) ->
          waiting.source.cast_id == cast_id && ending(waiting.unit_id)
        Error(Nil) -> False
      }
    })
  let #(ended, kept) =
    dict.get(cast.on_creatures, cast_id)
    |> result.unwrap([])
    |> list.partition(fn(on) { ending(on.unit_id) })
  let on_creatures = case kept {
    [] -> dict.delete(cast.on_creatures, cast_id)
    [_, ..] -> dict.insert(cast.on_creatures, cast_id, kept)
  }
  #(
    State(..cast, on_creatures:),
    list.append(
      cancels,
      list.map(ended, fn(on) {
        TargetChangeEnds(unit_id: on.unit_id, life: on.life, source: on.source)
      }),
    ),
  )
}

/// How many rolls the go of `phase` of the live cast `cast_id` may take once its
/// round closed with `struck`: one for each type 37 condition among the gates of
/// the Proxies that start a child and of the gains that may be given
/// (`prerequisite.rolls_needed`). The connection draws that many from its seed and
/// no others, so a go with no type 37 condition moves no roll. A cast that is not
/// live takes none.
pub fn rolls_needed(
  cast cast: State,
  cast_id cast_id: Int,
  phase phase: Int,
  struck struck: List(Struck),
) -> Int {
  case dict.get(cast.casts, cast_id) {
    Error(Nil) -> 0
    Ok(live) -> {
      let spell = live.spell
      let proxies =
        proxies_with_targets(spell:, phase:, struck:, spent: live.spent)
      int.sum(
        list.flatten([
          list.map(proxies, fn(proxy) {
            condition_rolls_needed(caster_side(condition: proxy.condition))
          }),
          list.map(
            gains_of(spell:, phase:, proxies:, spent: live.spent),
            gain_rolls_needed,
          ),
          list.map(
            spell_plan.lasting_in_phase(spell:, phase:, spent: live.spent),
            fn(row) { condition_rolls_needed(row.condition) },
          ),
          list.map(
            spell_plan.removes_in_phase(spell:, phase:, spent: live.spent),
            fn(row) { condition_rolls_needed(row.condition) },
          ),
          list.map(
            spell_plan.modifiers_in_phase(spell:, phase:, spent: live.spent),
            fn(row) { condition_rolls_needed(row.condition) },
          ),
          list.map(
            spell_plan.forced_moves_in_phase(spell:, phase:, spent: live.spent),
            fn(row) { condition_rolls_needed(row.condition) },
          ),
          list.map(
            spell_plan.cooldown_modifiers_in_phase(
              spell:,
              phase:,
              spent: live.spent,
            ),
            fn(row) { condition_rolls_needed(row.condition) },
          ),
          list.map(
            spell_plan.stealth_in_phase(spell:, phase:, spent: live.spent),
            fn(row) { condition_rolls_needed(row.condition) },
          ),
          list.map(
            spell_plan.remove_stealth_in_phase(
              spell:,
              phase:,
              spent: live.spent,
            ),
            fn(row) { condition_rolls_needed(row.condition) },
          ),
          list.map(
            spell_plan.procs_in_phase(spell:, phase:, spent: live.spent),
            fn(row) { condition_rolls_needed(row.condition) },
          ),
          list.map(
            spell_plan.shield_heals_in_phase(spell:, phase:, spent: live.spent),
            fn(row) { condition_rolls_needed(row.condition) },
          ),
        ]),
      )
    }
  }
}

/// The rolls the check of a condition's gates takes: one for each type 37 condition
/// among them.
fn condition_rolls_needed(condition: spell_plan.Condition) -> Int {
  case condition {
    spell_plan.GatedOnCaster(gates:) ->
      int.sum(
        list.map(gates, fn(gate) {
          prerequisite.rolls_needed(prerequisite: gate)
        }),
      )
    spell_plan.Always
    | spell_plan.GatedOnTarget(..)
    | spell_plan.GatedOnCasterAndTarget(..) -> 0
  }
}

/// The gains of a go, in the order `gains_given` checks them: the spell's own of
/// the phase, then those of each of these Proxies.
fn gains_of(
  spell spell: Spell,
  phase phase: Int,
  proxies proxies: List(Proxy),
  spent spent: Option(Int),
) -> List(spell_plan.Gain) {
  list.append(
    spell_plan.gains_in_phase(spell:, phase:, spent:),
    list.flat_map(proxies, lifted_gains),
  )
}

/// The rolls the check of a gain's prerequisite takes; a ticking gain is not
/// checked.
fn gain_rolls_needed(gain: spell_plan.Gain) -> Int {
  case gain {
    spell_plan.TickingGain(..) | spell_plan.Gain(prerequisite: None, ..) -> 0
    spell_plan.Gain(prerequisite: Some(gate), ..) ->
      prerequisite.rolls_needed(prerequisite: gate)
  }
}

/// The Proxies of the phase that the cast's n chooses and that have a unit to start a
/// child on: one aimed at the caster always, one aimed at each struck unit when the
/// round has a Hit.
fn proxies_with_targets(
  spell spell: Spell,
  phase phase: Int,
  struck struck: List(Struck),
  spent spent: Option(Int),
) -> List(Proxy) {
  let hit = hit_units(struck:) != []
  list.filter(spell_plan.proxies_in_phase(spell:, phase:, spent:), fn(proxy) {
    case proxy.target {
      spell_plan.OnCaster -> True
      spell_plan.OnEachStruck -> hit
    }
  })
}

/// The gains of a Proxy's child that the go of its parent gives once (the gains the
/// plan lifted onto the Proxy); none for a Proxy that is never started.
fn lifted_gains(proxy proxy: Proxy) -> List(spell_plan.Gain) {
  case proxy.condition {
    spell_plan.Always | spell_plan.GatedOnCaster(..) -> proxy.gains
    spell_plan.GatedOnTarget(..) | spell_plan.GatedOnCasterAndTarget(..) -> []
  }
}

/// The round of a go closed with `struck`, the units it named in the order of its
/// selection: the go's 0x7f4 with a target info for each (target flags 0), the
/// 0x7fb of the deflected ones, the spell's own cooldown at its first go, the
/// Proxies of the phase (a Proxy aimed at each struck unit starts one child for each
/// Hit unit and none for a deflect, and none for a Proxy whose gate against the
/// caster does not pass) and the finish after the last go. A cast that is no longer
/// live, because the client ended it while the round was open, has no go and writes
/// nothing: the hits stand. `poses` are the Hit units' ground points and yaws as the
/// caster's picture holds them when the round closes, by unit id, which a Proxy's target
/// gate reads (`children`); a Hit unit with none is not shown any more. `rolls` are the
/// rolls the go's type 37 conditions take (`rolls_needed`), in the order the conditions
/// are checked.
pub fn went(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
  cast_id cast_id: Int,
  phase phase: Int,
  struck struck: List(Struck),
  poses poses: Dict(Int, area.Pose),
  rolls rolls: List(Int),
) -> #(State, List(Effect)) {
  use <- settled(cast:, caster:, now:, own: [])
  released(
    taken: go(
      cast:,
      caster:,
      now_ms: now.monotonic_ms,
      cast_id:,
      phase:,
      struck:,
      poses:,
      rolls:,
    ),
    caster:,
    now_ms: now.monotonic_ms,
  )
  |> continued(caster:, now_ms: now.monotonic_ms)
}

/// A go of a live cast is asked: its first go pays the cast's reserved costs, then
/// the connection selects its targets and strikes them, and answers with `went` when
/// the round closes. A cast that is not live has no go.
fn asked(
  cast cast: State,
  cast_id cast_id: Int,
  phase phase: Int,
) -> #(State, List(Effect)) {
  case dict.get(cast.casts, cast_id) {
    Error(Nil) -> #(cast, [])
    Ok(live) -> {
      // The first go pays what the accept reserved as its strike begins: creatures
      // apply the round's hits as soon as they are told, so they are always paid for,
      // and the go's gates and gains read the paid caster (the server's choice: the
      // order at one go is not recorded).
      let reserved = live.reserved
      let live = Live(..live, reserved: [])
      #(
        State(..cast, casts: dict.insert(cast.casts, cast_id, live)),
        list.append(paying(payments: reserved), [
          Strike(asked: GoAsked(
            cast_id:,
            phase:,
            spell4_id: live.spell.spell4_id,
            primary_target: live.primary_target,
            spent: live.spent,
          )),
        ]),
      )
    }
  }
}

/// A cast that holds nodes, live or lingering, as the rules of lasting effects read
/// it.
type Holder {
  Holder(
    spell: Spell,
    audience: Set(ConnectionId),
    started_ms: Int,
    primary_target: Int,
    nodes: Dict(Int, lasting.Node),
    /// Whether the cast has gone for the last time and waits for its nodes to end.
    lingering: Bool,
  )
}

/// The cast `cast_id` as a holder of nodes, live or lingering.
fn holder_of(cast cast: State, cast_id cast_id: Int) -> Result(Holder, Nil) {
  case dict.get(cast.casts, cast_id), dict.get(cast.lingering, cast_id) {
    Ok(live), _ ->
      Ok(Holder(
        spell: live.spell,
        audience: live.audience,
        started_ms: live.started_ms,
        primary_target: live.primary_target,
        nodes: live.nodes,
        lingering: False,
      ))
    Error(Nil), Ok(lingering) ->
      Ok(Holder(
        spell: lingering.spell,
        audience: lingering.audience,
        started_ms: lingering.started_ms,
        primary_target: lingering.primary_target,
        nodes: lingering.nodes,
        lingering: True,
      ))
    Error(Nil), Error(Nil) -> Error(Nil)
  }
}

/// Every cast that holds nodes, live or lingering, in cast id order.
fn holders(cast cast: State) -> List(#(Int, Holder)) {
  list.append(dict.keys(cast.casts), dict.keys(cast.lingering))
  |> list.sort(int.compare)
  |> list.filter_map(fn(cast_id) {
    holder_of(cast:, cast_id:)
    |> result.map(fn(holder) { #(cast_id, holder) })
  })
}

/// The nodes of the cast set, wherever the cast is.
fn with_nodes(
  cast cast: State,
  cast_id cast_id: Int,
  nodes nodes: Dict(Int, lasting.Node),
) -> State {
  case dict.get(cast.casts, cast_id), dict.get(cast.lingering, cast_id) {
    Ok(live), _ ->
      State(
        ..cast,
        casts: dict.insert(cast.casts, cast_id, Live(..live, nodes:)),
      )
    Error(Nil), Ok(lingering) ->
      State(
        ..cast,
        lingering: dict.insert(
          cast.lingering,
          cast_id,
          Lingering(..lingering, nodes:),
        ),
      )
    Error(Nil), Error(Nil) -> cast
  }
}

/// The nodes whose life is over at the time, and the others, each with its unit id.
fn ended_and_kept(
  nodes nodes: Dict(Int, lasting.Node),
  now_ms now_ms: Int,
) -> #(List(#(Int, lasting.Node)), List(#(Int, lasting.Node))) {
  dict.to_list(nodes)
  |> list.partition(fn(entry) { life_over(life: { entry.1 }.life, now_ms:) })
}

/// The earliest node of the cast `cast_id` has ended, live or lingering: the nodes
/// whose life is over are dropped and written 0x811, and the timer starts again for the
/// next end. A lingering cast left with no node ends with its 0x7fe instead. A cast
/// that holds nothing any more has no frame.
fn nodes_ended(
  cast cast: State,
  cast_id cast_id: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case holder_of(cast:, cast_id:) {
    Error(Nil) -> #(cast, [])
    Ok(holder) -> {
      let #(ended, kept) = ended_and_kept(nodes: holder.nodes, now_ms:)
      case ended {
        [] -> rearmed(cast:, cast_id:, now_ms:)
        [_, ..] -> {
          let #(cast, started) =
            cooldowns_started_at_node_end(
              cast:,
              cast_id:,
              spell: holder.spell,
              unit_ids: sorted_units(ended),
              now_ms:,
            )
          let #(cast, healed) =
            heals_landed_at_node_end(
              cast:,
              cast_id:,
              unit_ids: sorted_units(ended),
            )
          let #(cast, modifiers) =
            caster_modifiers_ended(
              cast:,
              cast_id:,
              spell: holder.spell,
              unit_ids: sorted_units(ended),
            )
          let #(cast, on_creatures) =
            creature_modifiers_ended(
              cast:,
              cast_id:,
              unit_ids: sorted_units(ended),
            )
          let #(cast, left) =
            nodes_left(
              cast:,
              cast_id:,
              holder:,
              nodes: dict.from_list(kept),
              now_ms:,
            )
          #(
            cast,
            list.flatten([
              nodes_ended_frames(cast_id:, holder:, ended:, kept:),
              started,
              healed,
              modifiers,
              on_creatures,
              left,
            ]),
          )
        }
      }
    }
  }
}

/// What the end of some of a cast's nodes writes: the 0x7fe of a lingering cast left with
/// none, else 0x811 for the units whose node ended, with the cast destroyed on the client
/// when it has no node left and its method is not one the client keeps.
fn nodes_ended_frames(
  cast_id cast_id: Int,
  holder holder: Holder,
  ended ended: List(#(Int, lasting.Node)),
  kept kept: List(#(Int, lasting.Node)),
) -> List(Effect) {
  case holder.lingering && kept == [] {
    True -> finished_effects(cast_id:, audience: holder.audience)
    False ->
      targets_removed_effects(
        cast_id:,
        unit_ids: sorted_units(ended),
        audience: holder.audience,
        destroyed: kept == []
          && !keeps_without_target(method: holder.spell.method),
      )
  }
}

/// The cast's nodes after some left: a lingering cast with none left is dropped; any
/// other keeps the nodes it has, with its `NodesEnd` timer started again for them.
fn nodes_left(
  cast cast: State,
  cast_id cast_id: Int,
  holder holder: Holder,
  nodes nodes: Dict(Int, lasting.Node),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case holder.lingering && dict.is_empty(nodes) {
    True -> {
      let #(cast, cancels) = cancel_nodes_end(cast:, cast_id:)
      #(
        passive_cleared(
          cast: State(..cast, lingering: dict.delete(cast.lingering, cast_id)),
          cast_id:,
        ),
        cancels,
      )
    }
    False ->
      rearmed(cast: with_nodes(cast:, cast_id:, nodes:), cast_id:, now_ms:)
  }
}

/// Whether a node's life is over at the time: it ended, or it never had one.
fn life_over(life life: lasting.Life, now_ms now_ms: Int) -> Bool {
  case life {
    lasting.EndsAt(ms:) -> ms <= now_ms
    lasting.NoLife -> True
    lasting.UntilRemoved -> False
  }
}

/// The unit ids of nodes, in unit id order.
fn sorted_units(nodes: List(#(Int, lasting.Node))) -> List(Int) {
  list.map(nodes, fn(entry) { entry.0 }) |> list.sort(int.compare)
}

/// The earliest time a node ends at, none when every node lasts until it is removed.
fn earliest_end(nodes nodes: Dict(Int, lasting.Node)) -> Option(Int) {
  list.filter_map(dict.values(nodes), fn(node) {
    case node.life {
      lasting.EndsAt(ms:) -> Ok(ms)
      lasting.NoLife | lasting.UntilRemoved -> Error(Nil)
    }
  })
  |> list.reduce(int.min)
  |> option.from_result
}

/// The cast's `NodesEnd` timer, started for its earliest ending node; none when no
/// node ends by time.
fn arm_nodes_end(
  cast cast: State,
  cast_id cast_id: Int,
  nodes nodes: Dict(Int, lasting.Node),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case earliest_end(nodes:) {
    None -> #(cast, [])
    Some(ends_ms) -> {
      let #(cast, _, start) =
        armed(
          cast:,
          due: NodesEnd(cast_id:),
          after_ms: int.max(0, ends_ms - now_ms),
        )
      #(cast, [start])
    }
  }
}

/// The cast's `NodesEnd` timer cancelled and started again for the nodes it holds
/// now.
fn rearmed(
  cast cast: State,
  cast_id cast_id: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, cancels) = cancel_nodes_end(cast:, cast_id:)
  case holder_of(cast:, cast_id:) {
    Error(Nil) -> #(cast, cancels)
    Ok(holder) -> {
      let #(cast, armed) =
        arm_nodes_end(cast:, cast_id:, nodes: holder.nodes, now_ms:)
      #(cast, list.append(cancels, armed))
    }
  }
}

/// The `NodesEnd` timers of the cast cancelled.
fn cancel_nodes_end(
  cast cast: State,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  cancel_timers(cast:, matching: fn(due) {
    case due {
      NodesEnd(cast_id: waiting) -> waiting == cast_id
      Go(..)
      | Finish(..)
      | StartChild(..)
      | StateEnd(..)
      | ModifierStart(..)
      | TargetModifierStart(..)
      | ModifierEnd(..)
      | CooldownModifierStarts(..)
      | CooldownModifierEnds(..)
      | StartHeld
      | RepeatHeld
      | WindowEnd(..)
      | ChargeLevel(..) -> False
    }
  })
}

/// A unit the caster's client shows is removed from it (a 0x355 for a unit it was
/// shown): the client destroys that unit's nodes then (`0x1404550d0`), so the
/// unit's nodes are dropped from the live and lingering casts, and nothing is
/// written for them; a lingering cast left with no node sends its finish and is
/// dropped, and one that keeps nodes has its `NodesEnd` timer started again. This
/// bounds the casts that linger by the units in sight, so the caster's cast ids
/// (`mint`) cannot run out. A property modifier a dropped cast node held on a creature
/// ends with it (`TargetChangeEnds`), since nothing else would end it.
pub fn unit_removed(
  cast cast: State,
  unit_id unit_id: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, cancels) =
    cancel_timers(cast:, matching: fn(due) {
      case due {
        StateEnd(unit_id: waiting, ..) -> waiting == unit_id
        Go(..)
        | Finish(..)
        | StartChild(..)
        | NodesEnd(..)
        | ModifierStart(..)
        | TargetModifierStart(..)
        | ModifierEnd(..)
        | CooldownModifierStarts(..)
        | CooldownModifierEnds(..)
        | StartHeld
        | RepeatHeld
        | WindowEnd(..)
        | ChargeLevel(..) -> False
      }
    })
  list.filter(holders(cast:), fn(entry) {
    dict.has_key({ entry.1 }.nodes, unit_id)
  })
  |> list.fold(#(cast, cancels), fn(so_far, entry) {
    let #(cast, effects) = so_far
    let #(cast_id, holder) = entry
    let nodes = dict.delete(holder.nodes, unit_id)
    let #(cast, on_creatures) =
      creature_modifiers_ended(cast:, cast_id:, unit_ids: [unit_id])
    let #(cast, left) = nodes_left(cast:, cast_id:, holder:, nodes:, now_ms:)
    let ends = case holder.lingering && dict.is_empty(nodes) {
      True -> finished_effects(cast_id:, audience: holder.audience)
      False -> []
    }
    #(cast, list.flatten([effects, on_creatures, left, ends]))
  })
}

/// The player left the world with casts live: every timer is cancelled and nothing is
/// written; each property modifier the casts hold on a creature is told ended
/// (`TargetChangeEnds`), the creature's own, in cast id order.
pub fn left(cast cast: State) -> #(State, List(Effect)) {
  let on_creatures =
    dict.to_list(cast.on_creatures)
    |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
    |> list.flat_map(fn(entry) {
      list.map(entry.1, fn(on) {
        TargetChangeEnds(unit_id: on.unit_id, life: on.life, source: on.source)
      })
    })
  #(
    State(
      ..cast,
      casts: dict.new(),
      lingering: dict.new(),
      timers: dict.new(),
      held: None,
      holding: None,
      current: None,
      thresholds: dict.new(),
      cooldowns: cooldown.drop_all(book: cast.cooldowns),
      stealth: dict.new(),
      procs: dict.new(),
      passive: None,
      on_creatures: dict.new(),
    ),
    list.append(
      list.map(dict.keys(cast.timers), fn(timer) { CancelTimer(timer:) }),
      on_creatures,
    ),
  )
}

/// The caster died: each live cast ends with its timers cancelled and 0x7fe to
/// the caster and the audience that was told its start, in cast id order, and its nodes
/// with it, where a 0x801 lets them linger (`end_live_cast`); then the held press, the hold and every open
/// threshold end, and every other timer is cancelled, as when the player leaves
/// (`left`). The client does not end its own casts when it dies (not read,
/// `0x14045e740`), so the server's 0x7fe is the end its viewers see. Every stealth
/// source drops, and a stealthed caster's `StealthChanged` comes after the casts'
/// 0x7fe, followed by the casts of the procs the death fires: the `Died` procs first,
/// then those for the stealth it ended. The innate passive's cast is the one cast it
/// leaves: it stays live or lingering with its nodes, its modifiers, its pending timers,
/// its stealth sources and its procs, and nothing is written for it
/// (`passive_set_aside`).
pub fn died(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
) -> #(State, List(Effect)) {
  use <- settled(cast:, caster:, now:, own: [spell_plan.Died])
  all_ended(cast:, now:)
}

/// The caster left combat: the combat flag of its life (genesis_prime/game/player_life
/// `CombatLeft`) went off. The only effects are the casts of the procs held for it.
pub fn combat_left(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
) -> #(State, List(Effect)) {
  use <- settled(cast:, caster:, now:, own: [spell_plan.LeftCombat])
  #(cast, [])
}

/// Whether some live or lingering cast holds a spell with a persistence column, so
/// `persisted` has something to check: the connection asks before it builds the caster,
/// since most inputs find nothing.
pub fn persists(cast cast: State) -> Bool {
  list.any(holders(cast:), fn(entry) {
    has_persistence(spell: { entry.1 }.spell)
  })
}

fn has_persistence(spell spell: Spell) -> Bool {
  option.is_some(spell.caster_persistence)
  || option.is_some(spell.target_persistence)
}

/// The end of an input in the world: each live or lingering cast whose spell's
/// persistence condition no longer holds ends, in cast id order, the lowest first,
/// checked again after each end (it can break another's condition), and a press held
/// for the current cast it cleared starts. The client never evaluates a persistence
/// column (`Spell4.prerequisiteIdCasterPersistence`), so when to check and how to end
/// are the server's: after every input, which is exact and needs no timer. A cast ends
/// with 0x7f9 {cast id, 282 or 283, the caster, 0}, which destroys its nodes and so ends
/// its buff, then the 0x7fe that takes it out of the client's table, and is told to the
/// audience as a finish (`opcode.0x7f9`, `cast.target_node_end`). CasterPersistence
/// (282) is checked before TargetPersistence (283), the caster the first unit and the
/// cast's primary target the second; TargetPersistence is checked only for a cast the
/// caster itself is the target of, since no creature's state is held here. A press held
/// for the current cast it cleared starts, and a held key repeats, as after any input;
/// the casts they start are checked in turn. A condition
/// of a type not read, a roll (none is drawn) and a creature target keep the cast, with
/// one debug line for the spell.
pub fn persisted(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
) -> #(State, List(Effect)) {
  use <- settled(cast:, caster:, now:, own: [])
  let now_ms = now.monotonic_ms
  let #(cast, ended) = persistence_ended(cast:, caster:, now_ms:, done: [])
  let #(cast, effects) =
    released(taken: #(cast, ended), caster:, now_ms:)
    |> continued(caster:, now_ms:)
  // A press the end let start, or a repeat of a held key, starts a cast whose own
  // persistence may already fail.
  let #(cast, more) =
    persistence_ended(
      cast:,
      caster: after_payments(caster:, effects:),
      now_ms:,
      done: [],
    )
  #(cast, list.append(effects, more))
}

/// The casts that fail their persistence ended one at a time, the lowest cast id first,
/// until none fails.
fn persistence_ended(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  done done: List(Effect),
) -> #(State, List(Effect)) {
  let subject = subject_of(cast:, caster:)
  let #(cast, logs, failing) =
    first_failing_persistence(
      cast:,
      caster:,
      subject:,
      holders: holders(cast:),
      logs: [],
    )
  case failing {
    None -> #(cast, list.append(done, logs))
    Some(#(cast_id, result)) -> {
      let #(cast, ended) =
        persistence_end(cast:, caster:, now_ms:, cast_id:, result:)
      persistence_ended(
        cast:,
        caster:,
        now_ms:,
        done: list.flatten([done, logs, ended]),
      )
    }
  }
}

/// The first cast, in the order given, whose persistence fails, with its result and the
/// debug lines of the casts checked on the way.
fn first_failing_persistence(
  cast cast: State,
  caster caster: Caster,
  subject subject: prerequisite.Subject,
  holders holders: List(#(Int, Holder)),
  logs logs: List(Effect),
) -> #(State, List(Effect), Option(#(Int, cast_result.CastResult))) {
  case holders {
    [] -> #(cast, logs, None)
    [#(cast_id, holder), ..rest] -> {
      let #(cast, more, failing) =
        persistence_of(cast:, caster:, subject:, holder:)
      let logs = list.append(logs, more)
      case failing {
        Some(result) -> #(cast, logs, Some(#(cast_id, result)))
        None ->
          first_failing_persistence(
            cast:,
            caster:,
            subject:,
            holders: rest,
            logs:,
          )
      }
    }
  }
}

/// The result a cast's persistence fails with, none when it holds or cannot be read.
fn persistence_of(
  cast cast: State,
  caster caster: Caster,
  subject subject: prerequisite.Subject,
  holder holder: Holder,
) -> #(State, List(Effect), Option(cast_result.CastResult)) {
  let spell = holder.spell
  let #(cast, caster_logs, caster_fails) =
    persistence_column(
      cast:,
      spell:,
      result: cast_result.PrereqCasterPersistence,
      gate: spell.caster_persistence,
      subject: prerequisite.Subject(
        ..subject,
        second_unit: Some(holder.primary_target),
      ),
    )
  use <- bool.guard(when: caster_fails, return: #(
    cast,
    caster_logs,
    Some(cast_result.PrereqCasterPersistence),
  ))
  let #(cast, target_logs, target_fails) = case
    holder.primary_target == caster.unit_id
  {
    True ->
      persistence_column(
        cast:,
        spell:,
        result: cast_result.PrereqTargetPersistence,
        gate: spell.target_persistence,
        subject:,
      )
    False ->
      case spell.target_persistence {
        None -> #(cast, [], False)
        Some(_) -> {
          let #(cast, log) =
            logged_once(
              cast:,
              spell:,
              result: cast_result.PrereqTargetPersistence,
              text: "has a target persistence on a creature, whose state this connection does not hold, so it is not checked",
            )
          #(cast, log, False)
        }
      }
  }
  #(cast, list.append(caster_logs, target_logs), case target_fails {
    True -> Some(cast_result.PrereqTargetPersistence)
    False -> None
  })
}

/// One persistence column checked: whether it fails, and the debug line when it cannot
/// be read, once for the spell.
fn persistence_column(
  cast cast: State,
  spell spell: Spell,
  result result: cast_result.CastResult,
  gate gate: Option(prerequisite.Prerequisite),
  subject subject: prerequisite.Subject,
) -> #(State, List(Effect), Bool) {
  case column_verdict(gate:, subject:) {
    prerequisite.Passes -> #(cast, [], False)
    prerequisite.Fails -> #(cast, [], True)
    prerequisite.NotRead(prerequisite_type:) -> {
      let #(cast, log) =
        logged_once(
          cast:,
          spell:,
          result:,
          text: "has a persistence of the PrerequisiteType "
            <> int.to_string(prerequisite_type)
            <> ", which the server does not read, so its casts go on",
        )
      #(cast, log, False)
    }
  }
}

/// A debug line about the spell's persistence column of this result, unless one was
/// written already on this connection.
fn logged_once(
  cast cast: State,
  spell spell: Spell,
  result result: cast_result.CastResult,
  text text: String,
) -> #(State, List(Effect)) {
  let key = #(spell.spell4_id.value, cast_result.to_value(result))
  use <- bool.guard(
    when: set.contains(cast.persistence_logged, key),
    return: #(cast, []),
  )
  #(
    State(..cast, persistence_logged: set.insert(cast.persistence_logged, key)),
    [
      Log(
        level: LogDebug,
        text: "the cast of Spell4 "
          <> int.to_string(spell.spell4_id.value)
          <> " "
          <> text,
      ),
    ],
  )
}

/// A cast whose persistence failed ends as a death ends one cast: 0x7f9 with the
/// result, its go, finish and NodesEnd timers cancelled, its property modifiers and
/// cooldown effects ended, the current cast cleared when it was this one, an open
/// threshold it is the base cast of closed as a 0x801 closes it, and its 0x7fe to the
/// caster and the audience.
fn persistence_end(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  cast_id cast_id: Int,
  result result: cast_result.CastResult,
) -> #(State, List(Effect)) {
  let failure = failed_effect(cast_id:, result:, unit_id: caster.unit_id)
  case dict.get(cast.casts, cast_id), dict.get(cast.lingering, cast_id) {
    Ok(live), _ -> {
      let #(cast, cancels) = stop_pending(cast:, cast_id:)
      let #(cast, nodes) = cancel_nodes_end(cast:, cast_id:)
      let #(cast, ended) = effects_ended(cast:, cast_id:, spell: live.spell)
      let #(cast, on_creatures) = creature_modifiers_all_ended(cast:, cast_id:)
      let #(cast, finished) = case open_charge_of(cast:, cast_id:) {
        Some(threshold) ->
          close_threshold(cast:, ability: threshold.ability, now_ms:)
        None -> finish(cast:, cast_id:, live:, now_ms:)
      }
      #(
        cast,
        list.flatten([
          [failure],
          cancels,
          nodes,
          ended,
          on_creatures,
          finished,
        ]),
      )
    }
    Error(Nil), Ok(lingering) -> {
      let cast = State(..cast, lingering: dict.delete(cast.lingering, cast_id))
      let #(cast, nodes) = cancel_nodes_end(cast:, cast_id:)
      let #(cast, ended) =
        effects_ended(cast:, cast_id:, spell: lingering.spell)
      let #(cast, on_creatures) = creature_modifiers_all_ended(cast:, cast_id:)
      #(
        passive_cleared(cast:, cast_id:),
        list.flatten([
          [failure],
          nodes,
          ended,
          on_creatures,
          finished_effects(cast_id:, audience: lingering.audience),
        ]),
      )
    }
    Error(Nil), Error(Nil) -> #(cast, [])
  }
}

/// 0x7f9 for a cast that failed with this result: the bit is the 0 the 0x7fe path passes
/// (`opcode.0x7f9`). The unit is the caster, not the 0 the 0x7fe path passes: FinishCast
/// releases the threshold of a RapidTap cast ended with a result other than 6 or 8 only
/// when the end names another unit (`0x14053e1b0`), and this rule keeps the threshold of a
/// stage it ends open (only a charge's base cast closes its own), so the unit must not be
/// another; the 0x7fe path's result 8 never touches a threshold, which is why 0 is safe
/// there.
fn failed_effect(
  cast_id cast_id: Int,
  result result: cast_result.CastResult,
  unit_id unit_id: Int,
) -> Effect {
  let assert Ok(body) =
    spell_failed.encode(SpellFailed(cast_id:, result:, unit_id:, field_4: 0))
    as "a cast id of 32 bits, a result of 9, a unit id of 32 and a bit fit the message"
  Send(frame: Frame(message_id: spell_failed.message_id, body:))
}

/// The player's innate passive, the plans' spell of this Spell4Base, starts: a cast of
/// the player's own with its caster as root, no parent and its primary target, written
/// as 0x7ff with no 0x7fd, which runs no check of the caster and starts no global
/// cooldown (`Passive`). It starts at each join, alive or dead. A base the plans do not
/// hold is a warning and no cast.
pub fn passive_started(
  cast cast: State,
  caster caster: Caster,
  plans plans: Plans,
  base base: Spell4BaseId,
  now now: Now,
) -> #(State, List(Effect)) {
  case spell_plan.in_plans(plans:, base:) {
    Error(Nil) -> #(cast, [
      Log(
        level: LogWarning,
        text: "the innate passive with Spell4Base "
          <> int.to_string(base.value)
          <> " is in no plan, so it is not started",
      ),
    ])
    Ok(spell) ->
      start(
        cast:,
        caster:,
        now_ms: now.monotonic_ms,
        spell:,
        root: spell.spell4_id,
        parent: None,
        primary_target: caster.unit_id,
        client_cast_id: None,
        role: Passive,
        spent: None,
        reserved: [],
      )
  }
}

/// The caster's casts, press, hold, thresholds and timers ended by its death.
fn all_ended(cast cast: State, now now: Now) -> #(State, List(Effect)) {
  let #(cast, aside) = passive_set_aside(cast:)
  let #(cast, ended) =
    dict.to_list(cast.casts)
    |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
    |> list.fold(#(cast, []), fn(so_far, entry) {
      let #(cast, effects) = so_far
      let #(cast, cancels) = stop_pending(cast:, cast_id: entry.0)
      let #(cast, more) =
        finish(cast:, cast_id: entry.0, live: entry.1, now_ms: now.monotonic_ms)
      #(cast, list.flatten([effects, cancels, more]))
    })
  // A lingering cast ends with its 0x7fe when its caster dies: the server's choice,
  // since the client has no path that ends a buff on a unit's death
  // (`cast.target_node_end`).
  let lingering_ended =
    dict.to_list(cast.lingering)
    |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
    |> list.flat_map(fn(entry) {
      finished_effects(cast_id: entry.0, audience: { entry.1 }.audience)
    })
  let modifiers_ended = modifiers_pending(cast:)
  let #(cast, cancelled) = left(cast:)
  #(
    passive_restored(cast:, aside:),
    list.flatten([ended, lingering_ended, modifiers_ended, cancelled]),
  )
}

/// What a death leaves of the innate passive: its live or lingering cast, the timers
/// that belong to its tree, and the stealth sources and the procs it holds.
type Aside {
  Aside(
    id: Int,
    live: Option(Live),
    lingering: Option(Lingering),
    timers: List(#(TimerId, Due)),
    stealth: List(#(unit_properties.Source, spell_plan.Breaks)),
    procs: List(#(unit_properties.Source, HeldProc)),
    on_creatures: List(OnCreature),
  )
}

/// The cast without the passive's cast, timers, stealth sources and procs, and what was
/// taken out, when the passive has a cast.
fn passive_set_aside(cast cast: State) -> #(State, Option(Aside)) {
  case cast.passive {
    None -> #(cast, None)
    Some(id) -> {
      let live = dict.get(cast.casts, id) |> option.from_result
      let lingering = dict.get(cast.lingering, id) |> option.from_result
      let spell4_id = case live, lingering {
        Some(live), _ -> Some(live.spell.spell4_id)
        None, Some(lingering) -> Some(lingering.spell.spell4_id)
        None, None -> None
      }
      let #(timers, rest) =
        dict.to_list(cast.timers)
        |> list.partition(fn(entry) {
          belongs_to_passive(due: entry.1, id:, spell4_id:)
        })
      let #(stealth, others) = split_cast(held: cast.stealth, cast_id: id)
      let #(procs, other_procs) = split_cast(held: cast.procs, cast_id: id)
      case live, lingering {
        None, None -> #(cast, None)
        _, _ -> #(
          State(
            ..cast,
            casts: dict.delete(cast.casts, id),
            lingering: dict.delete(cast.lingering, id),
            timers: dict.from_list(rest),
            stealth: others,
            procs: other_procs,
            on_creatures: dict.delete(cast.on_creatures, id),
          ),
          Some(Aside(
            id:,
            live:,
            lingering:,
            timers:,
            stealth:,
            procs:,
            on_creatures: dict.get(cast.on_creatures, id) |> result.unwrap([]),
          )),
        )
      }
    }
  }
}

/// The cast with what `passive_set_aside` took out put back.
fn passive_restored(cast cast: State, aside aside: Option(Aside)) -> State {
  case aside {
    None -> cast
    Some(Aside(id:, live:, lingering:, timers:, stealth:, procs:, on_creatures:)) ->
      State(
        ..cast,
        on_creatures: case on_creatures {
          [] -> cast.on_creatures
          [_, ..] -> dict.insert(cast.on_creatures, id, on_creatures)
        },
        casts: case live {
          Some(live) -> dict.insert(cast.casts, id, live)
          None -> cast.casts
        },
        lingering: case lingering {
          Some(lingering) -> dict.insert(cast.lingering, id, lingering)
          None -> cast.lingering
        },
        timers: dict.merge(cast.timers, dict.from_list(timers)),
        stealth: dict.merge(cast.stealth, dict.from_list(stealth)),
        procs: dict.merge(cast.procs, dict.from_list(procs)),
        passive: Some(id),
      )
  }
}

/// Whether a timer belongs to the passive's own tree: one of its cast `id`, a modifier
/// or cooldown effect of that cast, or the start of a child whose root is its spell.
fn belongs_to_passive(
  due due: Due,
  id id: Int,
  spell4_id spell4_id: Option(Spell4Id),
) -> Bool {
  case due {
    Go(cast_id:, ..) | Finish(cast_id:) | NodesEnd(cast_id:) -> cast_id == id
    ModifierStart(source:, ..)
    | ModifierEnd(source:)
    | CooldownModifierStarts(source:, ..)
    | CooldownModifierEnds(source:) -> source.cast_id == id
    TargetModifierStart(on:, ..) -> on.source.cast_id == id
    StartChild(root:, ..) -> Some(root) == spell4_id
    StateEnd(..) | StartHeld | RepeatHeld | WindowEnd(..) | ChargeLevel(..) ->
      False
  }
}

/// The caster took damage: its health or its shield was lowered by a landed blow
/// (genesis_prime/game/player_life `DamageTaken`). Each cast that holds a stealth source
/// damage breaks loses its node on the caster, as a type 80 removal takes it off, and the
/// input ends with `StealthChanged` when the caster is no longer stealthed. A source kept
/// on damage stays (`Spell4Effects.effectType.83`: dataBits02).
pub fn damage_taken(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
) -> #(State, List(Effect)) {
  use <- settled(cast:, caster:, now:, own: [])
  broken_by_damage(cast:, caster:, now_ms: now.monotonic_ms)
}

/// Takes the node off the caster of each cast that holds a source damage breaks
/// (`damage_taken`); nothing when the caster holds none.
fn broken_by_damage(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let sources =
    dict.filter(cast.stealth, fn(_, breaks) {
      breaks == spell_plan.BrokenByDamage
    })
    |> dict.keys
  stealth_ended(cast:, caster:, sources:, now_ms:)
}

/// The casts that hold the stealth sources taken off the caster, oldest cast first, each
/// as a type 80 removal takes a cast off a unit (`node_off`: 0x811, and the 0x7fe of a
/// lingering cast of a method the client keeps), which drops every source of the cast
/// with its node (`effects_ended`).
fn stealth_ended(
  cast cast: State,
  caster caster: Caster,
  sources sources: List(unit_properties.Source),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let removals =
    list.map(sources, fn(source) { source.cast_id })
    |> list.unique
    |> list.sort(int.compare)
    |> list.map(fn(cast_id) {
      lasting.NodeOff(cast_id:, unit_id: caster.unit_id)
    })
  apply_removals(cast:, removals:, now_ms:)
}

/// Each property modifier the caster's casts may still hold, told ended in order: those
/// of the spells of its live and lingering casts, in cast id order, and those whose end
/// a timer waits for, in timer order; each once.
fn modifiers_pending(cast cast: State) -> List(Effect) {
  let held =
    list.flat_map(holders(cast:), fn(entry) {
      list.map(caster_rows(spell: { entry.1 }.spell), fn(row) {
        unit_properties.Source(cast_id: entry.0, effect_id: row.effect_id)
      })
    })
  let waiting =
    timers_in_order(cast:)
    |> list.filter_map(fn(entry) {
      case entry.1 {
        ModifierEnd(source:) -> Ok(source)
        ModifierStart(..)
        | TargetModifierStart(..)
        | CooldownModifierStarts(..)
        | CooldownModifierEnds(..)
        | Go(..)
        | Finish(..)
        | StartChild(..)
        | NodesEnd(..)
        | StateEnd(..)
        | StartHeld
        | RepeatHeld
        | WindowEnd(..)
        | ChargeLevel(..) -> Error(Nil)
      }
    })
  list.unique(list.append(held, waiting))
  |> list.map(fn(source) { CasterChangeEnds(source:) })
}

/// The timers the rule waits on with what each is for, in the order they were started.
fn timers_in_order(cast cast: State) -> List(#(TimerId, Due)) {
  dict.to_list(cast.timers)
  |> list.sort(fn(first, second) {
    let TimerId(first_number) = first.0
    let TimerId(second_number) = second.0
    int.compare(first_number, second_number)
  })
}

/// The id the caster's next cast takes: the id of its next press that no live or
/// lingering cast holds (the client keeps a lingering cast until its 0x7fe). `start` and the hold that records the cast it starts both ask this, so
/// they name the same cast.
fn next_cast_id(cast cast: State, caster caster: Caster) -> Int {
  mint(
    unit_id: caster.unit_id,
    number: cast.presses,
    live: list.append(dict.keys(cast.casts), dict.keys(cast.lingering)),
  )
}

/// A cast of the spell starts: its id, the start written to the caster (0x7fd for
/// a press, 0x7ff for a child) and told to the audience, the global cooldown, the
/// threshold's message and timers when the cast opens or moves one, the timer of
/// each later go and of a channel's finish, and the first go at once when it has
/// no wait.
fn start(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  spell spell: Spell,
  root root: Spell4Id,
  parent parent: Option(Spell4Id),
  primary_target primary_target: Int,
  client_cast_id client_cast_id: Option(Int),
  role role: Role,
  spent spent: Option(Int),
  reserved reserved: List(Payment),
) -> #(State, List(Effect)) {
  let id = next_cast_id(cast:, caster:)
  let audience = caster.audience
  let go_times = spell_plan.go_times_ms(spell:)
  let gos =
    list.index_map(go_times, fn(wait_ms, phase) {
      #(wait_ms, Go(cast_id: id, phase:))
    })
    |> list.filter(fn(go) { go.0 > 0 })
  let finishing = case spell_plan.finish_after_ms(spell:) {
    Some(wait_ms) -> [#(wait_ms, Finish(cast_id: id))]
    None -> []
  }
  let #(cast, timer_effects) =
    list.fold(list.append(gos, finishing), #(cast, []), fn(so_far, wait) {
      let #(cast, effects) = so_far
      let #(cast, _, start) = armed(cast:, due: wait.1, after_ms: wait.0)
      #(cast, list.append(effects, [start]))
    })
  let start_message =
    started_message(id:, spell:, root:, parent:, primary_target:, caster:)
  let live =
    Live(
      spell:,
      spent:,
      reserved:,
      root:,
      parent:,
      primary_target:,
      audience:,
      gone: 0,
      started_ms: now_ms,
      stage_of: case role {
        Stage(ability:, ..) -> Some(ability)
        Child | Base(..) | Passive -> None
      },
      closes_threshold: closes_threshold(role:),
      nodes: dict.new(),
    )
  let global_ends = case role, spell.global_cooldown.starts_for_ms {
    Passive, _ -> cast.global_cooldown_ends_ms
    Child, Some(wait_ms) | Base(..), Some(wait_ms) | Stage(..), Some(wait_ms) ->
      Some(now_ms + wait_ms)
    Child, None | Base(..), None | Stage(..), None ->
      cast.global_cooldown_ends_ms
  }
  let cast =
    State(
      ..cast,
      presses: cast.presses + 1,
      global_cooldown_ends_ms: global_ends,
      casts: dict.insert(cast.casts, id, live),
      passive: case role {
        Passive -> Some(id)
        Child | Base(..) | Stage(..) -> cast.passive
      },
      current: case
        role != Passive
        && spell_plan.shows_cast_bar(spell:, pressed: root == spell.spell4_id)
      {
        True -> Some(id)
        False -> cast.current
      },
    )
  let to_caster = case client_cast_id {
    Some(client_cast_id) ->
      confirmed_frame(client_cast_id:, start: start_message)
    None -> started_frame(start: start_message)
  }
  let told =
    list.map(map.sorted_connections(audience), fn(viewer) {
      Tell(
        to: viewer,
        news: client_connection.CastStarted(start: start_message),
      )
    })
  let #(cast, threshold_effects) = threshold_step(cast:, role:, cast_id: id)
  let opening =
    list.flatten([
      [Send(frame: to_caster)],
      told,
      threshold_effects,
      timer_effects,
    ])
  case go_times {
    [0, ..] -> {
      let #(cast, going) = asked(cast:, cast_id: id, phase: 0)
      #(cast, list.append(opening, going))
    }
    _ -> #(cast, opening)
  }
}

/// Whether the finish of a cast that is a stage closes its ability's threshold: a
/// release always does, a tap only when it is the last stage.
fn closes_threshold(role role: Role) -> Bool {
  case role {
    Child | Base(..) | Passive -> False
    Stage(ability:, index:) ->
      case ability.method {
        spell_plan.ChargeRelease -> True
        spell_plan.RapidTap -> index + 1 >= list.length(ability.stages)
        spell_plan.Normal
        | spell_plan.Channeled
        | spell_plan.PressHold
        | spell_plan.ChanneledField
        | spell_plan.ClientSideInteraction
        | spell_plan.Multiphase
        | spell_plan.Transactional
        | spell_plan.OtherMethod(..) -> False
      }
  }
}

/// The threshold's part of a cast's start: the ability's own spell opens one
/// (0x816, with its time or its charge timer), and a tap that is not the last
/// moves the index of a RapidTap one (0x817).
fn threshold_step(
  cast cast: State,
  role role: Role,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  case role {
    Child | Passive -> #(cast, [])
    Base(ability:) ->
      case spell_plan.opens_threshold(spell: ability) {
        True -> open_threshold(cast:, ability:, cast_id:)
        False -> #(cast, [])
      }
    Stage(ability:, index:) ->
      case dict.get(cast.thresholds, ability.spell4_id.value) {
        Error(Nil) -> #(cast, [])
        Ok(threshold) -> {
          let next = index + 1
          case
            ability.method == spell_plan.RapidTap
            && next < list.length(ability.stages)
          {
            True -> #(
              State(
                ..cast,
                thresholds: dict.insert(
                  cast.thresholds,
                  ability.spell4_id.value,
                  Threshold(..threshold, index: next),
                ),
              ),
              [
                Send(frame: index_frame(
                  spell4_id: ability.spell4_id,
                  index: next,
                )),
              ],
            )
            False -> #(cast, [])
          }
        }
      }
  }
}

/// The ability's first press opens its threshold at index 0: 0x816 with the base
/// cast's id, and the timer of its time (RapidTap) or of its first charge level
/// (ChargeRelease).
fn open_threshold(
  cast cast: State,
  ability ability: Spell,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  let cast =
    State(
      ..cast,
      thresholds: dict.insert(
        cast.thresholds,
        ability.spell4_id.value,
        Threshold(ability:, index: 0, cast_id:),
      ),
    )
  let opened = Send(frame: opened_frame(spell4_id: ability.spell4_id, cast_id:))
  case ability.method {
    spell_plan.RapidTap -> {
      let #(cast, _, start) =
        armed(
          cast:,
          due: WindowEnd(spell4_id: ability.spell4_id.value),
          after_ms: ability.threshold_ms,
        )
      #(cast, [opened, start])
    }
    spell_plan.ChargeRelease -> {
      let #(cast, waiting) = charge_timer(cast:, ability:, level: 1)
      #(cast, [opened, ..waiting])
    }
    spell_plan.Normal
    | spell_plan.Channeled
    | spell_plan.PressHold
    | spell_plan.ChanneledField
    | spell_plan.ClientSideInteraction
    | spell_plan.Multiphase
    | spell_plan.Transactional
    | spell_plan.OtherMethod(..) -> #(cast, [opened])
  }
}

/// The timer of the charge level `level`, after the row's thresholdDuration, when
/// the ability has that row.
fn charge_timer(
  cast cast: State,
  ability ability: Spell,
  level level: Int,
) -> #(State, List(Effect)) {
  case list.drop(ability.stages, level) |> list.first {
    Error(Nil) -> #(cast, [])
    Ok(stage) -> {
      let #(cast, _, start) =
        armed(
          cast:,
          due: ChargeLevel(spell4_id: ability.spell4_id.value, level:),
          after_ms: stage.duration_ms,
        )
      #(cast, [start])
    }
  }
}

/// The charge reaches `level`: 0x817, and the timer of the next level.
fn charge_level_reached(
  cast cast: State,
  spell4_id spell4_id: Int,
  level level: Int,
) -> #(State, List(Effect)) {
  case dict.get(cast.thresholds, spell4_id) {
    Error(Nil) -> #(cast, [])
    Ok(threshold) -> {
      let cast =
        State(
          ..cast,
          thresholds: dict.insert(
            cast.thresholds,
            spell4_id,
            Threshold(..threshold, index: level),
          ),
        )
      let #(cast, waiting) =
        charge_timer(cast:, ability: threshold.ability, level: level + 1)
      #(cast, [
        Send(frame: index_frame(
          spell4_id: threshold.ability.spell4_id,
          index: level,
        )),
        ..waiting
      ])
    }
  }
}

/// A RapidTap threshold's time ran out: the client closes it by itself, so the
/// server writes nothing, closes its own and starts the ability's cooldown
/// (`opcode.0x816`).
fn window_ended(
  cast cast: State,
  spell4_id spell4_id: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case dict.get(cast.thresholds, spell4_id) {
    Error(Nil) -> #(cast, [])
    Ok(threshold) -> #(
      start_cooldown(
        cast: State(..cast, thresholds: dict.delete(cast.thresholds, spell4_id)),
        spell: threshold.ability,
        now_ms:,
      ),
      [],
    )
  }
}

/// The ability's threshold closes: its timers are cancelled and 0x814 is sent. A
/// RapidTap one starts the ability's cooldown with the bit; a ChargeRelease one
/// ends its base cast with 0x7fe after the 0x814.
fn close_threshold(
  cast cast: State,
  ability ability: Spell,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let key = ability.spell4_id.value
  case dict.get(cast.thresholds, key) {
    Error(Nil) -> #(cast, [])
    Ok(threshold) -> {
      let #(cast, cancels) =
        cancel_timers(cast:, matching: fn(due) {
          case due {
            WindowEnd(spell4_id:) | ChargeLevel(spell4_id:, ..) ->
              spell4_id == key
            Go(..)
            | Finish(..)
            | StartChild(..)
            | NodesEnd(..)
            | StateEnd(..)
            | ModifierStart(..)
            | TargetModifierStart(..)
            | ModifierEnd(..)
            | CooldownModifierStarts(..)
            | CooldownModifierEnds(..)
            | StartHeld
            | RepeatHeld -> False
          }
        })
      let cast = State(..cast, thresholds: dict.delete(cast.thresholds, key))
      case ability.method {
        spell_plan.RapidTap -> #(
          start_cooldown(cast:, spell: ability, now_ms:),
          list.append(cancels, [
            Send(frame: closed_frame(
              spell4_id: ability.spell4_id,
              start_cooldowns: 1,
            )),
          ]),
        )
        spell_plan.ChargeRelease -> {
          let closed =
            Send(frame: closed_frame(
              spell4_id: ability.spell4_id,
              start_cooldowns: 0,
            ))
          let #(cast, ended) =
            end_base_cast(cast:, cast_id: threshold.cast_id, now_ms:)
          #(cast, list.flatten([cancels, [closed], ended]))
        }
        spell_plan.Normal
        | spell_plan.Channeled
        | spell_plan.PressHold
        | spell_plan.ChanneledField
        | spell_plan.ClientSideInteraction
        | spell_plan.Multiphase
        | spell_plan.Transactional
        | spell_plan.OtherMethod(..) -> #(cast, cancels)
      }
    }
  }
}

/// The base cast of a charge ends with its 0x7fe, when it is still live.
fn end_base_cast(
  cast cast: State,
  cast_id cast_id: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case dict.get(cast.casts, cast_id) {
    Ok(base) -> finish(cast:, cast_id:, live: base, now_ms:)
    Error(Nil) -> #(cast, [])
  }
}

/// The spell's own cooldown starts now, unless it is running already or the spell
/// has none. Its group cooldowns do not start: the server keeps none, so it is never
/// stricter than the client.
fn start_cooldown(
  cast cast: State,
  spell spell: Spell,
  now_ms now_ms: Int,
) -> State {
  State(
    ..cast,
    cooldowns: cooldown.start(
      book: cast.cooldowns,
      keys: cooldown.keys(
        spell4_id: spell.spell4_id,
        spell4_base_id: spell.spell4_base_id,
        spell_groups: spell.groups,
        cooldown_groups: spell.cooldown_groups,
      ),
      cooldown_ms: spell.cooldown_ms,
      now_ms:,
    ),
  )
}

/// The go of phase `phase` of a live cast, with the units its round struck: 0x7f4 to
/// the caster and the audience, then the 0x7fb of the deflected ones (the client
/// accepts either order and drops a miss after the finish, `cast.miss_order`), the
/// spell's own cooldown at the go its method names, the current cast cleared as the
/// client does, the Proxies of the phase whose gates pass, and the finish after the
/// last go. A cast that is not live has no go.
fn go(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  cast_id cast_id: Int,
  phase phase: Int,
  struck struck: List(Struck),
  poses poses: Dict(Int, area.Pose),
  rolls rolls: List(Int),
) -> #(State, List(Effect)) {
  case dict.get(cast.casts, cast_id) {
    Error(Nil) -> #(cast, [])
    Ok(live) -> {
      let spell = live.spell
      let go_count = spell_plan.go_count(spell:)
      let cast = case spell.cooldown_start {
        spell_plan.AtFirstGo if live.gone == 0 ->
          start_cooldown(cast:, spell:, now_ms:)
        spell_plan.AtLastGo if live.gone + 1 == go_count ->
          start_cooldown(cast:, spell:, now_ms:)
        spell_plan.AtFirstGo | spell_plan.AtLastGo | spell_plan.NotAtAGo -> cast
      }
      let cast = case live.stage_of {
        Some(ability)
          if spell.method == spell_plan.ChargeRelease && live.gone == 0
        -> start_cooldown(cast:, spell: ability, now_ms:)
        Some(_) | None -> cast
      }
      let current = case clears_current(cast:, live:, cast_id:) {
        True -> None
        False -> cast.current
      }
      let live = Live(..live, gone: live.gone + 1)
      let cast =
        State(..cast, current:, casts: dict.insert(cast.casts, cast_id, live))
      // The subject is read once here, before the children start and before the
      // finish: every gate of this go decides on the state before the go's own effects.
      let subject = subject_of(cast:, caster:)
      let #(starting, gate_logs, rolls) =
        proxy_gates(
          proxies: proxies_with_targets(
            spell:,
            phase:,
            struck:,
            spent: live.spent,
          ),
          subject:,
          rolls:,
        )
      let #(gains, rolls) =
        gains_given(
          spell:,
          phase:,
          starting:,
          subject:,
          rolls:,
          spent: live.spent,
        )
      let #(applied, lasting_logs, _) =
        lasting_applied(spell:, phase:, spent: live.spent, subject:, rolls:)
      let aimed = aimed_at(applied:, caster:, live:, struck:)
      let go_message =
        go_message(
          cast_id:,
          phase:,
          place: caster.place,
          struck:,
          listed: aimed.units,
        )
      let missed = missed_message(cast_id:, struck:)
      let going =
        list.flatten([
          [Send(frame: went_frame(go: go_message))],
          list.map(map.sorted_connections(live.audience), fn(viewer) {
            Tell(to: viewer, news: client_connection.CastWent(go: go_message))
          }),
          case missed {
            Some(missed) -> [
              Send(frame: missed_frame(missed:)),
              ..list.map(map.sorted_connections(live.audience), fn(viewer) {
                Tell(to: viewer, news: client_connection.CastMissed(missed:))
              })
            ]
            None -> []
          },
        ])
      let #(cast, removed) = removed_by_go(cast:, aimed:, now_ms:)
      let #(cast, logged) =
        states_logged(
          cast:,
          caster:,
          spell4_id: spell.spell4_id,
          aimed:,
          now_ms:,
        )
      let #(cast, given) = nodes_given(cast:, cast_id:, aimed:, now_ms:)
      let #(cast, never_held) = procs_held(cast:, cast_id:, applied:)
      let #(cast, modifying) =
        modifiers_armed(cast:, cast_id:, caster:, aimed:, struck:)
      let #(cast, healing) = heals_armed(cast:, cast_id:, aimed:)
      let #(cast, cooldowns) =
        cooldowns_armed(
          cast:,
          cast_id:,
          aimed:,
          longer_of_delay_and_duration: spell.longer_of_delay_and_duration,
          now_ms:,
        )
      let #(cast, children) =
        list.fold(starting, #(cast, []), fn(so_far, proxy) {
          let #(cast, effects) = so_far
          let #(cast, more) =
            children(
              cast:,
              caster:,
              now_ms:,
              live:,
              proxy:,
              struck:,
              subject:,
              poses:,
            )
          #(cast, list.append(effects, more))
        })
      let #(cast, stealth) =
        stealth_changed_by_go(
          cast:,
          caster:,
          cast_id:,
          spell:,
          applied:,
          last_go: live.gone >= go_count,
          now_ms:,
        )
      let #(cast, finished) = case
        live.gone == go_count
        && option.is_none(spell_plan.finish_after_ms(spell:))
      {
        True ->
          case dict.get(cast.casts, cast_id) {
            Ok(live) -> finish_or_linger(cast:, cast_id:, live:, now_ms:)
            Error(Nil) -> #(cast, [])
          }
        False -> #(cast, [])
      }
      // A cast that goes on after this go has its `NodesEnd` timer started for the
      // earliest end of its nodes; one that ended or lingers did that in its end.
      let #(cast, armed) = case
        nodes_aimed(aimed:) != [] && dict.has_key(cast.casts, cast_id)
      {
        True -> rearmed(cast:, cast_id:, now_ms:)
        False -> #(cast, [])
      }
      #(
        cast,
        list.flatten([
          going,
          logged,
          removed,
          given,
          never_held,
          modifying,
          healing,
          cooldowns,
          gains,
          gate_logs,
          lasting_logs,
          children,
          stealth,
          finished,
          armed,
        ]),
      )
    }
  }
}

/// What a go does to the caster's stealth, after the go's other effects: each Stealth row
/// that applied adds its source (the cast `cast_id`, the row's effect) with the row's
/// `Breaks`; a RemoveStealth row that applied ends every source; then a spell whose
/// `stealth_change` ends stealth at this go (`EndsStealthAtEachGo`, or
/// `EndsStealthAfterLastGo` when `last_go`) ends the sources of the other casts. A cast
/// never ends the sources of its own Stealth rows, whichever go applied them. A source
/// ends as `cast.stealth` loses it and its cast's node leaves the caster, as `node_off`
/// takes a type 80 removal's (0x811, and the 0x7fe of a lingering cast of a method the
/// client keeps). A go with no row, and no source to end, changes nothing.
///
/// A cast of `EndsStealthAfterLastGo` that stops before its last go does not reach this
/// for the goes it missed; `end_live_cast` ends the stealth when it stops after a go.
fn stealth_changed_by_go(
  cast cast: State,
  caster caster: Caster,
  cast_id cast_id: Int,
  spell spell: Spell,
  applied applied: Applied,
  last_go last_go: Bool,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case stealthed(cast:), applied.stealth, applied.remove_stealth {
    False, [], [] -> #(cast, [])
    _, _, _ -> {
      let cast =
        State(
          ..cast,
          stealth: list.fold(applied.stealth, cast.stealth, fn(held, row) {
            dict.insert(
              held,
              unit_properties.Source(cast_id:, effect_id: row.effect_id),
              row.breaks,
            )
          }),
        )
      let #(cast, removed) = case applied.remove_stealth {
        [] -> #(cast, [])
        [_, ..] ->
          stealth_ended(
            cast:,
            caster:,
            sources: dict.keys(cast.stealth),
            now_ms:,
          )
      }
      let #(cast, broken) = case spell.stealth_change, last_go {
        spell_plan.EndsStealthAtEachGo, _
        | spell_plan.EndsStealthAfterLastGo, True
        ->
          stealth_ended(
            cast:,
            caster:,
            sources: other_casts_sources(cast:, cast_id:),
            now_ms:,
          )
        spell_plan.EndsStealthAfterLastGo, False | spell_plan.KeepsStealth, _ -> #(
          cast,
          [],
        )
      }
      #(cast, list.append(removed, broken))
    }
  }
}

/// The Fluff and SpellForceRemove effects of a go that apply, after their gates
/// against the caster.
type Applied {
  Applied(
    lasting: List(spell_plan.Lasting),
    removes: List(spell_plan.ForceRemove),
    modifiers: List(spell_plan.PropertyModifier),
    forced_moves: List(spell_plan.ForcedMove),
    cooldowns: List(spell_plan.CooldownModifier),
    stealth: List(spell_plan.StealthRow),
    remove_stealth: List(spell_plan.RemoveStealthRow),
    procs: List(spell_plan.ProcRow),
    shield_heals: List(spell_plan.ShieldHeal),
  )
}

/// The Fluff, SpellForceRemove, property modifier, forced move, cooldown, Stealth,
/// RemoveStealth and HealShields effects of the phase whose gates pass against the caster,
/// a debug line for each that cannot be decided, and for each periodic heal that passes,
/// and the rolls left. Their gates are checked after the Proxies' and the gains', in that
/// order, the HealShields effects' last (`rolls_needed`).
fn lasting_applied(
  spell spell: Spell,
  phase phase: Int,
  spent spent: Option(Int),
  subject subject: prerequisite.Subject,
  rolls rolls: List(Int),
) -> #(Applied, List(Effect), List(Int)) {
  let #(lasting, logs, rolls) =
    gated(
      rows: spell_plan.lasting_in_phase(spell:, phase:, spent:),
      condition: fn(row: spell_plan.Lasting) { row.condition },
      what: fn(row: spell_plan.Lasting) {
        "the lasting effect " <> int.to_string(row.effect_id.value)
      },
      outcome: "so it is not applied",
      subject:,
      rolls:,
    )
  let #(removes, more_logs, rolls) =
    gated(
      rows: spell_plan.removes_in_phase(spell:, phase:, spent:),
      condition: fn(row: spell_plan.ForceRemove) { row.condition },
      what: fn(row: spell_plan.ForceRemove) {
        "the SpellForceRemove effect " <> int.to_string(row.effect_id.value)
      },
      outcome: "so it is not applied",
      subject:,
      rolls:,
    )
  let #(modifiers, modifier_logs, rolls) =
    gated(
      rows: list.filter(
        spell_plan.modifiers_in_phase(spell:, phase:, spent:),
        modifier_has_life,
      ),
      condition: fn(row: spell_plan.PropertyModifier) { row.condition },
      what: fn(row: spell_plan.PropertyModifier) {
        "the "
        <> modifier_kind_named(row:)
        <> " effect "
        <> int.to_string(row.effect_id.value)
      },
      outcome: "so it is not applied",
      subject:,
      rolls:,
    )
  let #(forced_moves, forced_move_logs, rolls) =
    gated(
      rows: spell_plan.forced_moves_in_phase(spell:, phase:, spent:),
      condition: fn(row: spell_plan.ForcedMove) { row.condition },
      what: fn(row: spell_plan.ForcedMove) {
        "the ForcedMove effect " <> int.to_string(row.effect_id.value)
      },
      outcome: "so it is not applied",
      subject:,
      rolls:,
    )
  let #(cooldowns, cooldown_logs, rolls) =
    gated(
      rows: spell_plan.cooldown_modifiers_in_phase(spell:, phase:, spent:),
      condition: fn(row: spell_plan.CooldownModifier) { row.condition },
      what: fn(row: spell_plan.CooldownModifier) {
        "the ModifySpellCooldown effect " <> int.to_string(row.effect_id.value)
      },
      outcome: "so it is not applied",
      subject:,
      rolls:,
    )
  let #(stealth, stealth_logs, rolls) =
    gated(
      rows: spell_plan.stealth_in_phase(spell:, phase:, spent:),
      condition: fn(row: spell_plan.StealthRow) { row.condition },
      what: fn(row: spell_plan.StealthRow) {
        "the Stealth effect " <> int.to_string(row.effect_id.value)
      },
      outcome: "so it is not applied",
      subject:,
      rolls:,
    )
  let #(remove_stealth, remove_stealth_logs, rolls) =
    gated(
      rows: spell_plan.remove_stealth_in_phase(spell:, phase:, spent:),
      condition: fn(row: spell_plan.RemoveStealthRow) { row.condition },
      what: fn(row: spell_plan.RemoveStealthRow) {
        "the RemoveStealth effect " <> int.to_string(row.effect_id.value)
      },
      outcome: "so it is not applied",
      subject:,
      rolls:,
    )
  let #(procs, proc_logs, rolls) =
    gated(
      rows: spell_plan.procs_in_phase(spell:, phase:, spent:),
      condition: fn(row: spell_plan.ProcRow) { row.condition },
      what: fn(row: spell_plan.ProcRow) {
        "the Proc effect " <> int.to_string(row.effect_id.value)
      },
      outcome: "so it is not applied",
      subject:,
      rolls:,
    )
  let #(heals, heal_logs, rolls) =
    gated(
      rows: spell_plan.shield_heals_in_phase(spell:, phase:, spent:),
      condition: fn(row: spell_plan.ShieldHeal) { row.condition },
      what: fn(row: spell_plan.ShieldHeal) {
        "the HealShields effect " <> int.to_string(row.effect_id.value)
      },
      outcome: "so it is not applied",
      subject:,
      rolls:,
    )
  let #(shield_heals, ticking_logs) = ticking_heals_logged(heals:)
  #(
    Applied(
      lasting:,
      removes:,
      modifiers:,
      forced_moves:,
      cooldowns:,
      stealth:,
      remove_stealth:,
      procs:,
      shield_heals:,
    ),
    list.flatten([
      logs,
      more_logs,
      modifier_logs,
      forced_move_logs,
      cooldown_logs,
      stealth_logs,
      remove_stealth_logs,
      proc_logs,
      heal_logs,
      ticking_logs,
    ]),
    rolls,
  )
}

/// The heals of a go that apply, and a debug line for each periodic heal whose gate
/// passed: a periodic heal needs a 0x7f8 for each tick, which the server does not send, so
/// it is not applied.
fn ticking_heals_logged(
  heals heals: List(spell_plan.ShieldHeal),
) -> #(List(spell_plan.ShieldHeal), List(Effect)) {
  let #(applying, ticking) =
    list.partition(heals, fn(heal) {
      case heal {
        spell_plan.ShieldHeal(..) -> True
        spell_plan.TickingShieldHeal(..) -> False
      }
    })
  #(
    applying,
    list.map(ticking, fn(heal) {
      Log(
        level: LogDebug,
        text: "the HealShields effect "
          <> int.to_string(heal.effect_id.value)
          <> " is periodic, and a periodic shield heal needs a 0x7f8 for each tick, which is not sent, so it is not applied",
      )
    }),
  )
}

/// What a go lists on one unit beside the damage it struck: the effect, its delay
/// and, for a crowd-control state, the instance id its tell gave (the other effects
/// are numbered by their place in the list, `target_info`) and, for a shield heal, the
/// damage description that shows it.
type Listed {
  Listed(
    effect_id: Spell4EffectsId,
    delay_ms: Int,
    instance_id: Option(Int),
    /// The description a heal carries, in place of the plain bit of the other effects.
    damage: Option(SpellDamageDescription),
  )
}

/// The units a go's applied effects aim at: each Fluff and type 80 row with the unit
/// it aims at, each crowd-control state a unit took with that unit, and the effects
/// listed on each unit in the order the units are listed.
type Aimed {
  Aimed(
    units: List(#(Int, List(Listed))),
    lasting: List(#(spell_plan.Lasting, Int)),
    removes: List(#(spell_plan.ForceRemove, Int)),
    modifiers: List(#(spell_plan.PropertyModifier, Int)),
    cooldowns: List(#(spell_plan.CooldownModifier, Int, Bool)),
    stealth: List(#(spell_plan.StealthRow, Int)),
    procs: List(#(spell_plan.ProcRow, Int)),
    heals: List(#(Healed, Int)),
    controls: List(#(strike_tell.ControlLanded, Int)),
  )
}

/// A shield heal a go applies: its row, its delay and the amount worked out at the go from
/// the caster as it stood before the go's own effects (genesis_prime/game/damage
/// `amount_on_caster`).
type Healed {
  Healed(effect_id: Spell4EffectsId, delay_ms: Int, amount: Int)
}

/// The units an effect aims at (`Spell4Effects.targetFlags`): the caster, the cast's
/// primary target, the units the round Hit, or the target and those.
fn units_aimed_at(
  aim aim: spell_plan.Aim,
  caster caster: Caster,
  primary_target primary_target: Int,
  struck struck: List(Struck),
) -> List(Int) {
  spell_plan.units_aimed_at(
    aim:,
    caster: caster.unit_id,
    primary_target:,
    area: hit_units(struck:),
  )
}

/// Each row with each unit its aim names.
fn rows_with_units(
  rows rows: List(row),
  aim aim: fn(row) -> spell_plan.Aim,
  caster caster: Caster,
  primary_target primary_target: Int,
  struck struck: List(Struck),
) -> List(#(row, Int)) {
  list.flat_map(rows, fn(row) {
    units_aimed_at(aim: aim(row), caster:, primary_target:, struck:)
    |> list.map(fn(unit_id) { #(row, unit_id) })
  })
}

/// Whether a modifier row takes effect on the unit its aim names: a change of the
/// caster's own (a property, a look, an absorb) on the caster, and a property modifier
/// aimed at struck units on a creature the go hit. One aimed at a unit that is the
/// caster or another player is left out until a modifier on another player is built
/// (#570).
fn modifier_applies(
  row row: spell_plan.PropertyModifier,
  unit_id unit_id: Int,
  caster caster: Caster,
  struck struck: List(Struck),
) -> Bool {
  case row.change {
    spell_plan.StruckChange(..) -> result.is_ok(creature_hit(struck:, unit_id:))
    spell_plan.PropertyChange(..)
    | spell_plan.LookChange(..)
    | spell_plan.AbsorbChange(..) -> unit_id == caster.unit_id
  }
}

/// The life of the creature `unit_id` the round hit and the time it was struck.
fn creature_hit(
  struck struck: List(Struck),
  unit_id unit_id: Int,
) -> Result(#(Int, Int), Nil) {
  list.find_map(struck, fn(one) {
    case one {
      Hit(unit_id: hit, unit: HitCreature(life:, struck_at_ms:), ..)
        if hit == unit_id
      -> Ok(#(life, struck_at_ms))
      Hit(..) | Deflected(..) -> Error(Nil)
    }
  })
}

fn aimed_at(
  applied applied: Applied,
  caster caster: Caster,
  live live: Live,
  struck struck: List(Struck),
) -> Aimed {
  let lasting =
    rows_with_units(
      rows: applied.lasting,
      aim: fn(row) { row.aim },
      caster:,
      primary_target: live.primary_target,
      struck:,
    )
  let removes =
    rows_with_units(
      rows: applied.removes,
      aim: fn(row) { row.aim },
      caster:,
      primary_target: live.primary_target,
      struck:,
    )
  let controls = controls_landed(struck:)
  let modifiers =
    rows_with_units(
      rows: applied.modifiers,
      aim: fn(row) { spell_plan.modifier_aim(modifier: row) },
      caster:,
      primary_target: live.primary_target,
      struck:,
    )
    |> list.filter(fn(entry) {
      modifier_applies(row: entry.0, unit_id: entry.1, caster:, struck:)
    })
  let forced_moves = applied.forced_moves
  let cooldowns =
    list.map(applied.cooldowns, fn(row) {
      #(
        row,
        caster.unit_id,
        cooldown_kept(
          row:,
          longer_of_delay_and_duration: live.spell.longer_of_delay_and_duration,
        ),
      )
    })
  let stealth = list.map(applied.stealth, fn(row) { #(row, caster.unit_id) })
  let procs = list.map(applied.procs, fn(row) { #(row, caster.unit_id) })
  let heals = healed_by(applied:, caster:, live:, struck:)
  let listed =
    list.flatten([
      list.map(stealth, fn(entry) {
        #(
          entry.1,
          Listed(
            effect_id: entry.0.effect_id,
            delay_ms: entry.0.row.delay_ms,
            instance_id: None,
            damage: None,
          ),
        )
      }),
      list.map(procs, fn(entry) {
        #(
          entry.1,
          Listed(
            effect_id: entry.0.effect_id,
            delay_ms: entry.0.row.delay_ms,
            instance_id: None,
            damage: None,
          ),
        )
      }),
      list.map(lasting, fn(entry) {
        #(
          entry.1,
          Listed(
            effect_id: entry.0.effect_id,
            delay_ms: entry.0.row.delay_ms,
            instance_id: None,
            damage: None,
          ),
        )
      }),
      list.map(modifiers, fn(entry) {
        #(
          entry.1,
          Listed(
            effect_id: entry.0.effect_id,
            delay_ms: entry.0.row.delay_ms,
            instance_id: None,
            damage: None,
          ),
        )
      }),
      list.map(forced_moves, fn(row) {
        #(
          caster.unit_id,
          Listed(
            effect_id: row.effect_id,
            delay_ms: row.delay_ms,
            instance_id: None,
            damage: None,
          ),
        )
      }),
      list.map(cooldowns, fn(entry) {
        #(
          entry.1,
          Listed(
            effect_id: entry.0.effect_id,
            delay_ms: entry.0.row.delay_ms,
            instance_id: None,
            damage: None,
          ),
        )
      }),
      list.map(removes, fn(entry) {
        #(
          entry.1,
          Listed(
            effect_id: entry.0.effect_id,
            delay_ms: 0,
            instance_id: None,
            damage: None,
          ),
        )
      }),
      list.map(heals, fn(entry) {
        #(
          entry.1,
          Listed(
            effect_id: entry.0.effect_id,
            delay_ms: entry.0.delay_ms,
            instance_id: None,
            damage: Some(heal_description(amount: entry.0.amount)),
          ),
        )
      }),
      list.map(controls, fn(entry) {
        #(
          entry.1,
          Listed(
            effect_id: Spell4EffectsId(entry.0.tell.effect_id),
            delay_ms: entry.0.tell.row.delay_ms,
            instance_id: Some(entry.0.tell.instance_id),
            damage: None,
          ),
        )
      }),
    ])
  let units =
    list.fold(listed, [], fn(units: List(#(Int, List(Listed))), entry) {
      case list.key_find(units, entry.0) {
        Ok(on_unit) ->
          list.key_set(units, entry.0, list.append(on_unit, [entry.1]))
        Error(Nil) -> list.append(units, [#(entry.0, [entry.1])])
      }
    })
  Aimed(
    units:,
    lasting:,
    removes:,
    modifiers:,
    cooldowns:,
    stealth:,
    heals:,
    procs:,
    controls:,
  )
}

/// The shield heals a go applies, each on the caster, with the amount the caster's own
/// vitals and stats give: the caster as it stood before the go's own effects, the rule of
/// every gate of the go (`subject_of`). A row's units are those its aim names
/// (`units_aimed_at`) and only the caster is healed: the plan reads a row aimed at the
/// primary target only in a spell cast on the caster
/// (genesis_prime/game/spell_plan `read_row`), and the server gives no other unit
/// a shield.
fn healed_by(
  applied applied: Applied,
  caster caster: Caster,
  live live: Live,
  struck struck: List(Struck),
) -> List(#(Healed, Int)) {
  let on_caster = on_caster_of(caster:)
  rows_with_units(
    rows: applied.shield_heals,
    aim: fn(heal: spell_plan.ShieldHeal) { heal.aim },
    caster:,
    primary_target: live.primary_target,
    struck:,
  )
  |> list.filter_map(fn(entry) {
    case entry.0, entry.1 == caster.unit_id {
      spell_plan.ShieldHeal(effect_id:, formula:, delay_ms:, ..), True ->
        Ok(#(
          Healed(
            effect_id:,
            delay_ms:,
            amount: damage.amount_on_caster(formula:, caster: on_caster),
          ),
          caster.unit_id,
        ))
      spell_plan.ShieldHeal(..), False | spell_plan.TickingShieldHeal(..), _ ->
        Error(Nil)
    }
  })
}

/// What a formula reads of the caster when it is also the target of its effect: the stats
/// and the vitals it had before the go's own effects (`subject_of`).
fn on_caster_of(caster caster: Caster) -> damage.OnCaster {
  damage.OnCaster(attacker: caster.stats, vitals: caster.vitals)
}

/// The damage description of a shield heal: the amount as the raw, the scaled raw and the
/// health change, a Hit of damage type HealShields (5), nothing absorbed or killed and no
/// hit entries (`Spell4Effects.effectType.118`, `GameLib.CodeEnumDamageType`,
/// `GameLib.CodeEnumCombatResult`). The raw values are the server's choice: the client
/// reads only the health change for a heal (`0x1405d8350`).
fn heal_description(amount amount: Int) -> SpellDamageDescription {
  SpellDamageDescription(
    raw_damage: amount,
    scaled_raw_damage: amount,
    absorbed: 0,
    shield_absorbed: 0,
    health_damage_with_overkill: amount,
    overkill: 0,
    glance: 0,
    killed: 0,
    combat_result: combat_result.Hit,
    damage_type: damage_type.HealShields,
    hits: [],
  )
}

/// What the row's effect type is called in a log line.
fn modifier_kind_named(row row: spell_plan.PropertyModifier) -> String {
  case row.armor, row.change {
    Some(..), _ -> "ModifyInterruptArmor"
    None, spell_plan.AbsorbChange(..) -> "Absorption"
    None, spell_plan.LookChange(..) -> "DisguiseOutfit"
    None, spell_plan.PropertyChange(..) | None, spell_plan.StruckChange(..) ->
      "UnitPropertyModifier or UnitPropertyConversion"
  }
}

/// Whether a modifier row has a time to be changed for: a durationTime, or flags bit 2.
/// A row with neither changes nothing and gives its node no life.
fn modifier_has_life(row: spell_plan.PropertyModifier) -> Bool {
  lasting.has_life(row: row.row)
}

/// Whether a cooldown row is kept for the cooldowns that start after it takes effect:
/// its lifetime (delay plus durationTime, the larger of the two for a spell with the
/// record flag 0x10000000) ends after its start, or never ends (flags bit 2). Any other
/// row acts once at its start (`0x14046b7f0`, `opcode.0x7f4.effect_time`). Every row
/// aimed at the caster gives its node the lifetime, kept or not.
fn cooldown_kept(
  row row: spell_plan.CooldownModifier,
  longer_of_delay_and_duration longer_of_delay_and_duration: Bool,
) -> Bool {
  row.row.until_removed
  || lasting.lifetime_of(row: row.row, longer_of_delay_and_duration:)
  > row.row.delay_ms
}

/// The caster's combat log of the states a go landed: an entry for each (0x247 of
/// type 1, removed 0), and a timer for each state's end entry (removed 1) at the time
/// the creature holds it until (`opcode.0x247.cc_state`). A state's end entry is never
/// written for a unit the caster's client stopped showing: `unit_removed` cancels it.
fn states_logged(
  cast cast: State,
  caster caster: Caster,
  spell4_id spell4_id: Spell4Id,
  aimed aimed: Aimed,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  list.fold(aimed.controls, #(cast, []), fn(so_far, entry) {
    let #(cast, effects) = so_far
    let #(landed, unit_id) = entry
    let state = landed.tell.row.state
    let #(cast, _, start) =
      armed(
        cast:,
        due: StateEnd(spell4_id:, unit_id:, state:),
        after_ms: int.max(0, landed.ends_at_ms - now_ms),
      )
    #(
      cast,
      list.append(effects, [
        Send(frame: control_logged_frame(
          caster_unit_id: caster.unit_id,
          unit_id:,
          spell4_id:,
          state:,
          removed: False,
        )),
        start,
      ]),
    )
  })
}

/// 0x247 of type 1: the state set on the unit by the caster's spell, or ended. The
/// Interrupt Armor it hit is 0 and its result Ok: a creature takes a state only with no
/// armor, and no diminishing returns apply (`opcode.0x247.cc_state`).
fn control_logged_frame(
  caster_unit_id caster_unit_id: Int,
  unit_id unit_id: Int,
  spell4_id spell4_id: Spell4Id,
  state state: CrowdControlState,
  removed removed: Bool,
) -> Frame {
  let assert Ok(body) =
    combat_log.encode(
      CombatLog(
        entry: combat_log_entry.CcState(CombatLogCcState(
          state:,
          removed: case removed {
            True -> 1
            False -> 0
          },
          interrupt_armor_hit: 0,
          result: crowd_control_result.Ok,
          diminishing_returns_id: 0,
          caster_unit_id:,
          target_unit_id: unit_id,
          spell4_id: spell4_id.value,
          combat_result: combat_result.Hit,
        )),
      ),
    )
    as "unit ids and a Spell4 id that fit their fields"
  Frame(message_id: combat_log.message_id, body:)
}

/// The crowd-control states the units of a go took, each with its unit, in the order
/// of the units.
fn controls_landed(
  struck struck: List(Struck),
) -> List(#(strike_tell.ControlLanded, Int)) {
  list.flat_map(struck, fn(one) {
    case one {
      Hit(unit_id:, controls:, ..) ->
        list.map(controls, fn(control) { #(control, unit_id) })
      Deflected(..) -> []
    }
  })
}

/// The type 80 effects of a go taken off the units they aim at, in order: each takes
/// the matching casts of the caster off the unit, oldest first, and writes 0x811 or
/// 0x813 for each (`opcode.0x811`, `opcode.0x813`).
fn removed_by_go(
  cast cast: State,
  aimed aimed: Aimed,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  list.fold(aimed.removes, #(cast, []), fn(so_far, entry) {
    let #(cast, effects) = so_far
    let #(row, unit_id) = entry
    let removals =
      lasting.removals(
        holds: holds_on(cast:, unit_id:),
        selector: row.selector,
        count: row.count,
        unit_id:,
      )
    let #(cast, more) = apply_removals(cast:, removals:, now_ms:)
    #(cast, list.append(effects, more))
  })
}

/// The property modifiers a go applies, each armed from this go: the modifier of an
/// earlier go of the cast is armed again, its timers cancelled and started anew; a row
/// with no delay starts in this step, any other on a timer of its delay, and one that
/// does not last until removed ends on a timer after its delay and duration.
fn modifiers_armed(
  cast cast: State,
  cast_id cast_id: Int,
  caster caster: Caster,
  aimed aimed: Aimed,
  struck struck: List(Struck),
) -> #(State, List(Effect)) {
  list.fold(aimed.modifiers, #(cast, []), fn(so_far, entry) {
    let #(cast, effects) = so_far
    let row = entry.0
    let source = unit_properties.Source(cast_id:, effect_id: row.effect_id)
    let #(cast, more) = case row.change {
      spell_plan.StruckChange(modifier:, ..) ->
        creature_modifier_armed(
          cast:,
          cast_id:,
          row:,
          modifier:,
          unit_id: entry.1,
          struck:,
        )
      spell_plan.PropertyChange(modifier:) ->
        caster_modifier_armed(cast:, row:, source:, change: Property(modifier:))
      spell_plan.LookChange(disguise:) ->
        caster_modifier_armed(cast:, row:, source:, change: Look(disguise:))
      spell_plan.AbsorbChange(absorption:) ->
        // An absorb's pool is worked out at the go from the caster as it stood before
        // the go's own effects, as a shield heal's amount is (`healed_by`).
        caster_modifier_armed(
          cast:,
          row:,
          source:,
          change: Absorb(
            amount: damage.amount_on_caster(
              formula: absorption.formula,
              caster: on_caster_of(caster:),
            ),
            mask: absorption.mask,
          ),
        )
    }
    #(cast, list.append(effects, more))
  })
}

/// A property modifier on a creature the go struck, armed from this go: the modifier
/// of an earlier go on the same creature is armed again; a row with no delay starts in
/// this step and any other on a timer of its delay. It has no timer of its end: it ends
/// with the cast's node on the creature (`creature_modifiers_ended`).
fn creature_modifier_armed(
  cast cast: State,
  cast_id cast_id: Int,
  row row: spell_plan.PropertyModifier,
  modifier modifier: unit_properties.Modifier,
  unit_id unit_id: Int,
  struck struck: List(Struck),
) -> #(State, List(Effect)) {
  case creature_hit(struck:, unit_id:) {
    Error(Nil) -> #(cast, [])
    Ok(#(life, struck_at_ms)) -> {
      let on =
        OnCreature(
          unit_id:,
          life:,
          source: unit_properties.Source(cast_id:, effect_id: row.effect_id),
        )
      let #(cast, cancels) = target_start_cancelled(cast:, on:)
      case row.row.delay_ms > 0 {
        True -> {
          let #(cast, _, start) =
            armed(
              cast:,
              due: TargetModifierStart(on:, modifier:, struck_at_ms:),
              after_ms: row.row.delay_ms,
            )
          #(cast, list.append(cancels, [start]))
        }
        False -> {
          let #(cast, starting) =
            target_modifier_started(cast:, on:, modifier:, struck_at_ms:)
          #(cast, list.append(cancels, starting))
        }
      }
    }
  }
}

/// The start timer of the modifier `on` names cancelled, whichever go armed it.
fn target_start_cancelled(
  cast cast: State,
  on on: OnCreature,
) -> #(State, List(Effect)) {
  cancel_timers(cast:, matching: fn(due) {
    case target_start_of(due:) {
      Ok(waiting) ->
        waiting.unit_id == on.unit_id && waiting.source == on.source
      Error(Nil) -> False
    }
  })
}

/// The modifier on a creature a timer waits to start, none for any other timer.
fn target_start_of(due due: Due) -> Result(OnCreature, Nil) {
  case due {
    TargetModifierStart(on:, ..) -> Ok(on)
    Go(..)
    | Finish(..)
    | StartChild(..)
    | NodesEnd(..)
    | StateEnd(..)
    | ModifierStart(..)
    | ModifierEnd(..)
    | CooldownModifierStarts(..)
    | CooldownModifierEnds(..)
    | StartHeld
    | RepeatHeld
    | WindowEnd(..)
    | ChargeLevel(..) -> Error(Nil)
  }
}

/// A property modifier on the caster, armed from this go: the modifier of an earlier
/// go of the cast is armed again, its timers cancelled and started anew; a row with no
/// delay starts in this step, any other on a timer of its delay, and one that does not
/// last until removed ends on a timer after its delay and duration.
fn caster_modifier_armed(
  cast cast: State,
  row row: spell_plan.PropertyModifier,
  source source: unit_properties.Source,
  change change: CasterChange,
) -> #(State, List(Effect)) {
  {
    let #(cast, cancels) = cancel_source_timers(cast:, source:)
    let #(cast, starting) = case row.row.delay_ms > 0 {
      True -> {
        let #(cast, _, start) =
          armed(
            cast:,
            due: ModifierStart(source:, change:),
            after_ms: row.row.delay_ms,
          )
        #(cast, [start])
      }
      False -> #(cast, [CasterChangeStarts(source:, change:)])
    }
    let #(cast, ending) = case row.row.until_removed {
      True -> #(cast, [])
      False -> {
        let #(cast, _, start) =
          armed(
            cast:,
            due: ModifierEnd(source:),
            after_ms: row.row.delay_ms + row.row.duration_ms,
          )
        #(cast, [start])
      }
    }
    #(cast, list.flatten([cancels, starting, ending]))
  }
}

/// The shield heals a go applies: a heal with no delay lands in this step, after the go's
/// 0x7f4, and any other on a timer of its delay (the client adds the delay before it
/// applies a result, `0x1405d77a0`). Each go's heal is its own, so a later go of the cast
/// heals again and no earlier heal is cancelled; a pending heal is dropped with the node
/// of the cast on the caster (`effects_ended`), and lands when the node ends by time
/// (`heals_landed_at_node_end`).
fn heals_armed(
  cast cast: State,
  cast_id cast_id: Int,
  aimed aimed: Aimed,
) -> #(State, List(Effect)) {
  list.fold(aimed.heals, #(cast, []), fn(so_far, entry) {
    let #(cast, effects) = so_far
    let healed = entry.0
    let source = unit_properties.Source(cast_id:, effect_id: healed.effect_id)
    let change = ShieldHeal(amount: healed.amount)
    case healed.delay_ms > 0 {
      True -> {
        let #(cast, _, start) =
          armed(
            cast:,
            due: ModifierStart(source:, change:),
            after_ms: healed.delay_ms,
          )
        #(cast, list.append(effects, [start]))
      }
      False -> #(
        cast,
        list.append(effects, [CasterChangeStarts(source:, change:)]),
      )
    }
  })
}

/// The cooldown effects a go applies, each armed from this go: the effect of an
/// earlier go of the cast is armed again, its timers cancelled and started anew. A row
/// with no delay takes effect in this step and any other on a timer of its delay. A row
/// is kept for the cooldowns that start later when it is `cooldown_kept`; a kept row is
/// dropped on a timer at the end of its lifetime, unless it never ends.
fn cooldowns_armed(
  cast cast: State,
  cast_id cast_id: Int,
  aimed aimed: Aimed,
  longer_of_delay_and_duration longer_of_delay_and_duration: Bool,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  list.fold(aimed.cooldowns, #(cast, []), fn(so_far, entry) {
    let #(cast, effects) = so_far
    let row = entry.0
    let source = unit_properties.Source(cast_id:, effect_id: row.effect_id)
    let #(cast, cancels) = cancel_source_timers(cast:, source:)
    let lifetime_ms =
      lasting.lifetime_of(row: row.row, longer_of_delay_and_duration:)
    let kept = entry.2
    let #(cast, starting) = case row.row.delay_ms > 0 {
      True -> {
        let #(cast, _, start) =
          armed(
            cast:,
            due: CooldownModifierStarts(source:, modifier: row.modifier, kept:),
            after_ms: row.row.delay_ms,
          )
        #(cast, [start])
      }
      False ->
        cooldown_applied(cast:, source:, modifier: row.modifier, kept:, now_ms:)
    }
    let #(cast, ending) = case kept && !row.row.until_removed {
      True -> {
        let #(cast, _, start) =
          armed(
            cast:,
            due: CooldownModifierEnds(source:),
            after_ms: lifetime_ms,
          )
        #(cast, [start])
      }
      False -> #(cast, [])
    }
    #(cast, list.flatten([effects, cancels, starting, ending]))
  })
}

/// A cooldown effect takes effect: it is kept for the cooldowns that start later when
/// `kept`, and the running cooldowns it picks change. When one did, a press held for a
/// cooldown and the hold's repeat wait again for the new end (`waits_rearmed`).
fn cooldown_applied(
  cast cast: State,
  source source: unit_properties.Source,
  modifier modifier: cooldown.Modifier,
  kept kept: Bool,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let book = case kept {
    True -> cooldown.keep(book: cast.cooldowns, source:, modifier:)
    False -> cast.cooldowns
  }
  let changed = cooldown.modify(book:, modifier:, now_ms:)
  let cast = State(..cast, cooldowns: changed)
  case changed == book {
    True -> #(cast, [])
    False -> waits_rearmed(cast:, now_ms:)
  }
}

/// The wait of a press held for a cooldown's end and of the held ability's repeat is
/// worked out again after a cooldown moved: each timer is cancelled and started for the
/// new wait, which is a timer of 0 ms when the cooldown ended, so the step's own messages
/// go out first. The press waits for the end wherever it moves (the server's choice,
/// `cast.hold_repeat`).
fn waits_rearmed(
  cast cast: State,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, held) = case cast.held {
    Some(Held(resolution:, until: CooldownEnds, ..)) -> {
      let #(global_left, own_left) =
        cooldown_left_ms(cast:, spell: resolution.spell, now_ms:)
      let #(cast, cancels) =
        cancel_timers(cast:, matching: fn(due) { due == StartHeld })
      let #(cast, _, start) =
        armed(cast:, due: StartHeld, after_ms: int.max(global_left, own_left))
      #(cast, list.append(cancels, [start]))
    }
    Some(Held(until: CastClears, ..)) | None -> #(cast, [])
  }
  let #(cast, repeating) = case cast.holding {
    Some(Holding(ability:, repeat_timer: Some(_), ..)) ->
      case resolved(cast:, ability:) {
        Ok(resolution) -> {
          let #(cast, cancels) =
            cancel_timers(cast:, matching: fn(due) { due == RepeatHeld })
          let #(cast, start) =
            repeat_after(
              cast:,
              wait_ms: cooldown_wait_ms(cast:, spell: resolution.spell, now_ms:),
            )
          #(cast, list.append(cancels, start))
        }
        Error(Nil) -> #(cast, [])
      }
    Some(Holding(repeat_timer: None, ..)) | None -> #(cast, [])
  }
  #(cast, list.append(held, repeating))
}

/// The source an effect timer is for: a property modifier's, a shield heal's (a start is
/// the only timer a heal has) or a cooldown effect's. Effect ids are unique, so a source
/// names one row.
fn source_of(due due: Due) -> Option(unit_properties.Source) {
  case due {
    ModifierStart(source:, ..)
    | ModifierEnd(source:)
    | CooldownModifierStarts(source:, ..)
    | CooldownModifierEnds(source:) -> Some(source)
    TargetModifierStart(on:, ..) -> Some(on.source)
    Go(..)
    | Finish(..)
    | StartChild(..)
    | NodesEnd(..)
    | StateEnd(..)
    | StartHeld
    | RepeatHeld
    | WindowEnd(..)
    | ChargeLevel(..) -> None
  }
}

/// The timers of the effect `source` cancelled.
fn cancel_source_timers(
  cast cast: State,
  source source: unit_properties.Source,
) -> #(State, List(Effect)) {
  cancel_timers(cast:, matching: fn(due) { source_of(due:) == Some(source) })
}

/// The effects of the cast `cast_id` ended when its node on the caster is among the
/// nodes that leave `unit_ids`, whether taken off or ended by time.
fn caster_modifiers_ended(
  cast cast: State,
  cast_id cast_id: Int,
  spell spell: Spell,
  unit_ids unit_ids: List(Int),
) -> #(State, List(Effect)) {
  use <- bool.guard(
    when: !list.contains(unit_ids, caster_of(cast_id:)),
    return: #(cast, []),
  )
  effects_ended(cast:, cast_id:, spell:)
}

/// The modifier rows of a spell that change the caster: the rows aimed at struck units
/// are the creature's (`creature_modifiers_ended`).
fn caster_rows(spell spell: Spell) -> List(spell_plan.PropertyModifier) {
  list.filter(spell.modifiers, fn(row) {
    case row.change {
      spell_plan.StruckChange(..) -> False
      spell_plan.PropertyChange(..)
      | spell_plan.LookChange(..)
      | spell_plan.AbsorbChange(..) -> True
    }
  })
}

/// A row of a spell that ends with its node on the caster: a property modifier, which
/// is told ended, or a cooldown effect, which is dropped from the kept list.
type Ending {
  CasterChangeEnding(source: unit_properties.Source, until_removed: Bool)
  CooldownEnding(source: unit_properties.Source)
}

/// The effects of the cast `cast_id` ended, as its node leaves the caster: each source
/// of its spell's rows has its timers cancelled, and its stealth sources are dropped
/// (`stealth_dropped`). A property modifier that lasts until
/// removed or whose start or end a timer waited for is told ended, and a modifier whose
/// own end already fired is not told again. A cooldown effect is taken out of the kept
/// list; the cooldowns it changed stay changed, as on the client.
fn effects_ended(
  cast cast: State,
  cast_id cast_id: Int,
  spell spell: Spell,
) -> #(State, List(Effect)) {
  let endings =
    list.append(
      list.map(caster_rows(spell:), fn(row) {
        CasterChangeEnding(
          source: unit_properties.Source(cast_id:, effect_id: row.effect_id),
          until_removed: row.row.until_removed,
        )
      }),
      list.map(spell.cooldown_modifiers, fn(row) {
        CooldownEnding(source: unit_properties.Source(
          cast_id:,
          effect_id: row.effect_id,
        ))
      }),
    )
  let #(cast, effects) =
    list.fold(endings, #(cast, []), fn(so_far, ending) {
      let #(cast, effects) = so_far
      let held =
        list.any(dict.values(cast.timers), fn(due) {
          source_of(due:) == Some(ending.source)
        })
      let #(cast, cancels) = cancel_source_timers(cast:, source: ending.source)
      case ending {
        CasterChangeEnding(source:, until_removed:) if until_removed || held -> #(
          cast,
          list.flatten([effects, cancels, [CasterChangeEnds(source:)]]),
        )
        CasterChangeEnding(..) -> #(cast, list.append(effects, cancels))
        CooldownEnding(source:) -> #(
          State(..cast, cooldowns: cooldown.drop(book: cast.cooldowns, source:)),
          list.append(effects, cancels),
        )
      }
    })
  let #(cast, heal_cancels) = pending_heals_cancelled(cast:, cast_id:)
  #(
    procs_dropped(cast: stealth_dropped(cast:, cast_id:), cast_id:),
    list.append(effects, heal_cancels),
  )
}

/// The shield heals of the cast `cast_id` that a timer still waits to land, by timer id.
fn pending_heals(
  cast cast: State,
  cast_id cast_id: Int,
) -> List(#(TimerId, unit_properties.Source, Int)) {
  timers_in_order(cast:)
  |> list.filter_map(fn(entry) {
    case entry.1 {
      ModifierStart(source:, change: ShieldHeal(amount:))
        if source.cast_id == cast_id
      -> Ok(#(entry.0, source, amount))
      ModifierStart(..)
      | TargetModifierStart(..)
      | ModifierEnd(..)
      | CooldownModifierStarts(..)
      | CooldownModifierEnds(..)
      | Go(..)
      | Finish(..)
      | StartChild(..)
      | NodesEnd(..)
      | StateEnd(..)
      | StartHeld
      | RepeatHeld
      | WindowEnd(..)
      | ChargeLevel(..) -> Error(Nil)
    }
  })
}

/// The pending shield heals of the cast `cast_id` cancelled with their timers: the node
/// of the cast on the caster is gone, and the client's 0x811 or 0x7fe destroys the effect
/// still pending (`opcode.0x7fe`).
fn pending_heals_cancelled(
  cast cast: State,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  cancel_timers(cast:, matching: fn(due) {
    case due {
      ModifierStart(source:, change: ShieldHeal(..)) ->
        source.cast_id == cast_id
      ModifierStart(change: Property(..), ..)
      | ModifierStart(change: Absorb(..), ..)
      | ModifierStart(change: Look(..), ..)
      | TargetModifierStart(..)
      | ModifierEnd(..)
      | CooldownModifierStarts(..)
      | CooldownModifierEnds(..)
      | Go(..)
      | Finish(..)
      | StartChild(..)
      | NodesEnd(..)
      | StateEnd(..)
      | StartHeld
      | RepeatHeld
      | WindowEnd(..)
      | ChargeLevel(..) -> False
    }
  })
}

/// The shield heals of the cast `cast_id` that a timer still waits to land, landed now,
/// as the caster's node ends by time: a node lives as long as its longest effect, so a
/// heal's start falls in the millisecond of the node's end or before it, and the end
/// applies it first, whichever timer the shell delivers first. A node taken off lands
/// none (`effects_ended`).
fn heals_landed_at_node_end(
  cast cast: State,
  cast_id cast_id: Int,
  unit_ids unit_ids: List(Int),
) -> #(State, List(Effect)) {
  use <- bool.guard(
    when: !list.contains(unit_ids, caster_of(cast_id:)),
    return: #(cast, []),
  )
  let pending = pending_heals(cast:, cast_id:)
  let #(cast, cancels) = pending_heals_cancelled(cast:, cast_id:)
  #(
    cast,
    list.append(
      cancels,
      list.map(pending, fn(heal) {
        CasterChangeStarts(source: heal.1, change: ShieldHeal(amount: heal.2))
      }),
    ),
  )
}

/// The stealth sources of the cast `cast_id` dropped, as its node leaves the caster: the
/// stealth lasts as long as the node that holds it.
fn stealth_dropped(cast cast: State, cast_id cast_id: Int) -> State {
  State(..cast, stealth: without_cast(held: cast.stealth, cast_id:))
}

/// What a cast holds by source (its stealth sources, its procs) with the entries of the
/// cast `cast_id` left out.
fn without_cast(
  held held: Dict(unit_properties.Source, a),
  cast_id cast_id: Int,
) -> Dict(unit_properties.Source, a) {
  dict.filter(held, fn(source, _) { source.cast_id != cast_id })
}

/// What a cast holds by source, split in the entries of the cast `cast_id` and what is
/// left of it.
fn split_cast(
  held held: Dict(unit_properties.Source, a),
  cast_id cast_id: Int,
) -> #(List(#(unit_properties.Source, a)), Dict(unit_properties.Source, a)) {
  let #(of_cast, others) =
    dict.to_list(held)
    |> list.partition(fn(entry) { { entry.0 }.cast_id == cast_id })
  #(of_cast, dict.from_list(others))
}

/// The Proc rows of the cast `cast_id` dropped, as its node leaves the caster: a proc is
/// held as long as the node that holds it.
fn procs_dropped(cast cast: State, cast_id cast_id: Int) -> State {
  State(..cast, procs: without_cast(held: cast.procs, cast_id:))
}

/// The cooldown effects of the cast `cast_id` that a timer still waits to start, taken
/// effect as the caster's node ends by time, because a node lives at least as long as
/// every row's delay from the same go, so the row's start falls in the millisecond of
/// the node's end or before it. A node taken off, by a removal, a death or a leave, does
/// not apply them: the client's 0x811 or 0x7fe destroys the pending effect.
fn cooldowns_started_at_node_end(
  cast cast: State,
  cast_id cast_id: Int,
  spell spell: Spell,
  unit_ids unit_ids: List(Int),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  use <- bool.guard(
    when: !list.contains(unit_ids, caster_of(cast_id:)),
    return: #(cast, []),
  )
  list.fold(spell.cooldown_modifiers, #(cast, []), fn(so_far, row) {
    let #(cast, effects) = so_far
    let source = unit_properties.Source(cast_id:, effect_id: row.effect_id)
    let #(cast, cancels) =
      cancel_timers(cast:, matching: fn(due) {
        due
        == CooldownModifierStarts(source:, modifier: row.modifier, kept: False)
      })
    case cancels {
      [] -> #(cast, effects)
      [_, ..] -> {
        let #(cast, applied) =
          cooldown_applied(
            cast:,
            source:,
            modifier: row.modifier,
            kept: False,
            now_ms:,
          )
        #(cast, list.flatten([effects, cancels, applied]))
      }
    }
  })
}

/// The nodes a go gives, one for each unit a Fluff row aims at or a crowd-control state
/// landed on: count 1 and the longest life of its rows with the effects the cast's node on
/// the unit already holds (`lasting.given`: a later go keeps and re-arms them, as on the
/// client, `opcode.0x7f4.instance_count`), and at least until the time the creature
/// holds each state, which no later go moves; a unit left with no effect that has a life
/// and no state holds no node of the cast.
fn nodes_given(
  cast cast: State,
  cast_id cast_id: Int,
  aimed aimed: Aimed,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case dict.get(cast.casts, cast_id), nodes_aimed(aimed:) {
    Error(Nil), _ | _, [] -> #(cast, [])
    Ok(live), units -> {
      let given =
        units
        |> list.map(fn(unit_id) {
          #(
            unit_id,
            node_of(
              spell: live.spell,
              held: dict.get(live.nodes, unit_id) |> option.from_result,
              aimed:,
              unit_id:,
              now_ms:,
            ),
          )
        })
      let #(cast, pushed) =
        list.fold(given, #(cast, []), fn(so_far, entry) {
          case entry.1 {
            Ok(node) -> pushed_by(so_far:, cast_id:, live:, node:, now_ms:)
            Error(Nil) -> so_far
          }
        })
      let nodes = case dict.get(cast.casts, cast_id) {
        Ok(current) -> current.nodes
        Error(Nil) -> live.nodes
      }
      let nodes =
        list.fold(given, nodes, fn(nodes, entry) {
          case entry.1 {
            Ok(node) -> dict.insert(nodes, entry.0, node)
            Error(Nil) -> dict.delete(nodes, entry.0)
          }
        })
      #(with_nodes(cast:, cast_id:, nodes:), pushed)
    }
  }
}

/// The units a go gives a node: those a Fluff row aims at and those that took a
/// crowd-control state, each once, in that order. The state's life is its delay plus
/// its duration, so the caster's cast lingers until the state's effect is over and its
/// time readout stays right (`cc_state.end`).
fn nodes_aimed(aimed aimed: Aimed) -> List(Int) {
  list.unique(
    list.flatten([
      list.map(aimed.lasting, fn(entry) { entry.1 }),
      list.map(aimed.modifiers, fn(entry) { entry.1 }),
      list.map(aimed.cooldowns, fn(entry) { entry.1 }),
      list.map(aimed.stealth, fn(entry) { entry.1 }),
      list.map(aimed.procs, fn(entry) { entry.1 }),
      list.map(aimed.heals, fn(entry) { entry.1 }),
      list.map(aimed.controls, fn(entry) { entry.1 }),
    ]),
  )
}

/// The node a go gives one unit from the node its cast holds there and the Fluff rows
/// the go lists for it (`lasting.given`); none when no effect has a life.
fn node_of(
  spell spell: Spell,
  held held: Option(lasting.Node),
  aimed aimed: Aimed,
  unit_id unit_id: Int,
  now_ms now_ms: Int,
) -> Result(lasting.Node, Nil) {
  let rows =
    list.flatten([
      list.filter_map(aimed.lasting, fn(entry) {
        case entry.1 == unit_id {
          True -> Ok(entry.0.row)
          False -> Error(Nil)
        }
      }),
      list.filter_map(aimed.modifiers, fn(entry) {
        case entry.1 == unit_id {
          True -> Ok(entry.0.row)
          False -> Error(Nil)
        }
      }),
      list.filter_map(aimed.cooldowns, fn(entry) {
        case entry.1 == unit_id {
          True -> Ok(entry.0.row)
          False -> Error(Nil)
        }
      }),
      list.filter_map(aimed.stealth, fn(entry) {
        case entry.1 == unit_id {
          True -> Ok(entry.0.row)
          False -> Error(Nil)
        }
      }),
      list.filter_map(aimed.procs, fn(entry) {
        case entry.1 == unit_id {
          True -> Ok(entry.0.row)
          False -> Error(Nil)
        }
      }),
      list.filter_map(aimed.heals, fn(entry) {
        case entry.1 == unit_id {
          True ->
            Ok(lasting.LastingRow(
              delay_ms: { entry.0 }.delay_ms,
              duration_ms: 0,
              until_removed: False,
            ))
          False -> Error(Nil)
        }
      }),
    ])
  let held_until_ms =
    list.filter_map(aimed.controls, fn(entry) {
      case entry.1 == unit_id {
        True -> Ok(entry.0.ends_at_ms)
        False -> Error(Nil)
      }
    })
  lasting.given(
    held:,
    unit_id:,
    count: 1,
    effects: rows,
    held_until_ms:,
    longer_of_delay_and_duration: spell.longer_of_delay_and_duration,
    go_ms: now_ms,
  )
}

/// A node the go gives a unit its cast holds none on yet makes a new cast on that
/// unit, which pushes the caster's oldest casts of its stack off the unit at the cap
/// (Jim's decision, `lasting.pushed_off`); a unit the cast holds a node on already is a
/// later go of the same cast, which pushes nothing.
fn pushed_by(
  so_far so_far: #(State, List(Effect)),
  cast_id cast_id: Int,
  live live: Live,
  node node: lasting.Node,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  use <- bool.guard(
    when: dict.has_key(live.nodes, node.unit_id),
    return: so_far,
  )
  let #(cast, effects) = so_far
  let removals =
    lasting.pushed_off(
      holds: list.filter(holds_on(cast:, unit_id: node.unit_id), fn(hold) {
        hold.cast_id != cast_id
      }),
      spell4_id: live.spell.spell4_id,
      stack: live.spell.stack,
      unit_id: node.unit_id,
    )
  let #(cast, more) = apply_removals(cast:, removals:, now_ms:)
  #(cast, list.append(effects, more))
}

/// What the live and lingering casts hold on the unit, as removals, stacking and
/// prerequisites read it.
pub fn holds_on(cast cast: State, unit_id unit_id: Int) -> List(lasting.Hold) {
  list.filter_map(holders(cast:), fn(entry) {
    let #(cast_id, holder) = entry
    dict.get(holder.nodes, unit_id)
    |> result.map(fn(node) {
      lasting.Hold(
        cast_id:,
        spell4_id: holder.spell.spell4_id,
        base: holder.spell.spell4_base_id,
        groups: holder.spell.groups,
        stack: holder.spell.stack,
        started_ms: holder.started_ms,
        node:,
      )
    })
  })
}

/// What a removal does to the casts, in order: a cast that loses its whole node on a
/// unit is written 0x811 and keeps no node there, one that loses a stack is written
/// 0x813 and keeps its node one count lower. A lingering cast left with no node is
/// dropped, and, when its cast method is one the client keeps with no target
/// (Channeled, ChanneledField, Multiphase or 10), ends with its 0x7fe after the 0x811
/// (`opcode.0x811`).
fn apply_removals(
  cast cast: State,
  removals removals: List(lasting.Removal),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  list.fold(removals, #(cast, []), fn(so_far, removal) {
    let #(cast, effects) = so_far
    let #(cast, more) = case removal {
      lasting.NodeOff(cast_id:, unit_id:) ->
        node_off(cast:, cast_id:, unit_id:, now_ms:)
      lasting.StackOff(cast_id:, unit_id:) ->
        stack_off(cast:, cast_id:, unit_id:)
    }
    #(cast, list.append(effects, more))
  })
}

/// A cast loses its whole node on a unit: 0x811 for the unit, with the cast destroyed on
/// the client when it has no node left and its method is not one the client keeps; a
/// lingering cast with none left is dropped, with its 0x7fe after the 0x811 when the
/// client keeps a cast of its method.
fn node_off(
  cast cast: State,
  cast_id cast_id: Int,
  unit_id unit_id: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case holder_of(cast:, cast_id:) {
    Error(Nil) -> #(cast, [])
    Ok(holder) -> {
      let nodes = dict.delete(holder.nodes, unit_id)
      let emptied = dict.is_empty(nodes)
      let kept = keeps_without_target(method: holder.spell.method)
      let removed =
        targets_removed_effects(
          cast_id:,
          unit_ids: [unit_id],
          audience: holder.audience,
          destroyed: emptied && !kept,
        )
      let #(cast, modifiers) =
        caster_modifiers_ended(cast:, cast_id:, spell: holder.spell, unit_ids: [
          unit_id,
        ])
      let #(cast, on_creatures) =
        creature_modifiers_ended(cast:, cast_id:, unit_ids: [unit_id])
      let #(cast, left) = nodes_left(cast:, cast_id:, holder:, nodes:, now_ms:)
      let ends = case holder.lingering && emptied && kept {
        True -> finished_effects(cast_id:, audience: holder.audience)
        False -> []
      }
      #(cast, list.flatten([removed, modifiers, on_creatures, left, ends]))
    }
  }
}

/// Whether the client keeps a cast that has no target left, so its end must be
/// written (`opcode.0x811`: cast methods 1, 3, 8 and 10).
fn keeps_without_target(method method: spell_plan.CastMethod) -> Bool {
  case method {
    spell_plan.Channeled
    | spell_plan.ChanneledField
    | spell_plan.Multiphase
    | spell_plan.OtherMethod(10) -> True
    spell_plan.Normal
    | spell_plan.PressHold
    | spell_plan.ClientSideInteraction
    | spell_plan.RapidTap
    | spell_plan.ChargeRelease
    | spell_plan.Transactional
    | spell_plan.OtherMethod(..) -> False
  }
}

/// A cast loses one stack on a unit: 0x813 and its node one count lower. A node's
/// count is the 1 of an application, so a removal reaches this only for a node whose
/// count is higher (`opcode.0x7f4.instance_count`, `opcode.0x813`).
fn stack_off(
  cast cast: State,
  cast_id cast_id: Int,
  unit_id unit_id: Int,
) -> #(State, List(Effect)) {
  case holder_of(cast:, cast_id:) {
    Error(Nil) -> #(cast, [])
    Ok(holder) -> {
      let nodes = case dict.get(holder.nodes, unit_id) {
        Ok(node) ->
          dict.insert(
            holder.nodes,
            unit_id,
            lasting.Node(..node, count: int.max(0, node.count - 1)),
          )
        Error(Nil) -> holder.nodes
      }
      #(
        with_nodes(cast:, cast_id:, nodes:),
        stack_removed_effects(cast_id:, unit_id:, audience: holder.audience),
      )
    }
  }
}

/// 0x811 for the units, to the caster and told to the audience, with whether the
/// client destroys the cast with it.
fn targets_removed_effects(
  cast_id cast_id: Int,
  unit_ids unit_ids: List(Int),
  audience audience: Set(ConnectionId),
  destroyed destroyed: Bool,
) -> List(Effect) {
  let removed = SpellTargetsRemoved(cast_id:, unit_ids:)
  [
    Send(frame: targets_removed_frame(removed:)),
    ..list.map(map.sorted_connections(audience), fn(viewer) {
      Tell(
        to: viewer,
        news: client_connection.CastTargetsRemoved(removed:, destroyed:),
      )
    })
  ]
}

/// 0x813 for the unit, to the caster and told to the audience.
fn stack_removed_effects(
  cast_id cast_id: Int,
  unit_id unit_id: Int,
  audience audience: Set(ConnectionId),
) -> List(Effect) {
  let removed = SpellStackRemoved(cast_id:, unit_id:)
  [
    Send(frame: stack_removed_frame(removed:)),
    ..list.map(map.sorted_connections(audience), fn(viewer) {
      Tell(to: viewer, news: client_connection.CastStackRemoved(removed:))
    })
  ]
}

/// 0x7fe to the caster and told to the audience.
fn finished_effects(
  cast_id cast_id: Int,
  audience audience: Set(ConnectionId),
) -> List(Effect) {
  [
    Send(frame: finished_frame(cast_id:)),
    ..list.map(map.sorted_connections(audience), fn(viewer) {
      Tell(to: viewer, news: client_connection.CastFinished(cast_id:))
    })
  ]
}

/// What a prerequisite may read about the caster, with no roll: the live casts it is
/// the primary target of and what the live and lingering casts hold on it, whether it
/// is in combat, and its vitals: its health and
/// shield, and the one class resource slot it holds as Vital 5 to 11 (slots 0 to 6,
/// `0x1403b3320`: the cost check reads Vitals 5 to 11 as the caster's resource slots
/// 0 to 6; the getter type 71 and 73 call is not read case by case, so the same
/// mapping is taken for it). A slot the class does not hold is no vital, so a
/// prerequisite of it is not read. The same slot is the resource slot a type 64 condition
/// names by its number, and every other slot reads 0.0 as the client's unit holds it
/// (`class_resource`, `0x140454380`). A player holds no difficulty. The caster stands on
/// its own point, facing its own yaw, for both units of a type 108 condition
/// (`Spell4Effects.prerequisiteIdTargetApply`: the caster is both units of a caster-side
/// check).
fn subject_of(cast cast: State, caster caster: Caster) -> prerequisite.Subject {
  let slot = class_resource.slot(resources: caster.resources)
  let held = case slot >= 0 && slot <= 6 {
    True -> [
      #(
        slot + 5,
        prerequisite.Vital(
          current: class_resource.value(resources: caster.resources, slot:),
          maximum: class_resource.max(resources: caster.resources, slot:),
        ),
      ),
    ]
    False -> []
  }
  let pose = area.pose_of(place: caster.place)
  prerequisite.Subject(
    under: dict.values(cast.casts)
      |> list.filter(fn(live) { live.primary_target == caster.unit_id })
      |> list.map(fn(live) {
        lasting.Held(
          spell4_id: live.spell.spell4_id,
          caster: caster.unit_id,
          count: 0,
          groups: live.spell.groups,
        )
      })
      |> list.append(nodes_held(cast:, caster:)),
    second_unit: Some(caster.unit_id),
    in_combat: caster.in_combat,
    vitals: dict.merge(dict.from_list(held), caster.life_vitals),
    difficulty: None,
    stealthed: Some(stealthed(cast:)),
    resource_slots: Some(case slot >= 0 {
      True ->
        dict.from_list([
          #(slot, class_resource.value(resources: caster.resources, slot:)),
        ])
      False -> dict.new()
    }),
    rolls: [],
    positions: prerequisite.Placed(first: pose, second: pose),
    factions: Some(caster.factions),
    player: Some(caster.player),
    quests: Some(caster.quests),
    seen: prerequisite.WholeUnit,
  )
}

/// What the live and lingering casts hold on the caster's own unit, as a
/// prerequisite reads it.
fn nodes_held(cast cast: State, caster caster: Caster) -> List(lasting.Held) {
  list.map(holds_on(cast:, unit_id: caster.unit_id), fn(hold) {
    lasting.Held(
      spell4_id: hold.spell4_id,
      caster: caster.unit_id,
      count: hold.node.count,
      groups: hold.groups,
    )
  })
}

/// The prerequisite checked against the subject with the rolls its type 37
/// conditions take off the front of `rolls`, and the rolls left.
fn checked(
  prerequisite gate: prerequisite.Prerequisite,
  subject subject: prerequisite.Subject,
  rolls rolls: List(Int),
) -> #(prerequisite.Verdict, List(Int)) {
  let #(taken, left) =
    list.split(rolls, prerequisite.rolls_needed(prerequisite: gate))
  #(
    prerequisite.check(
      prerequisite: gate,
      subject: prerequisite.Subject(..subject, rolls: taken),
    ),
    left,
  )
}

/// What a Proxy's gate gives at a go.
type ProxyGate {
  /// Its child starts.
  Starts
  /// A gate fails: the client's answer, nothing to say.
  GateFails
  /// The server cannot tell, and `why` says so in a debug line.
  CannotTell(why: String)
}

/// A Proxy's condition as its go checks it against the caster: a Proxy behind a target gate
/// as well passes here on its caster gates alone, and `children` checks its target gate
/// for each unit its child would be made on.
fn caster_side(
  condition condition: spell_plan.Condition,
) -> spell_plan.Condition {
  case condition {
    spell_plan.GatedOnCasterAndTarget(caster:, ..) ->
      spell_plan.GatedOnCaster(gates: caster)
    spell_plan.Always
    | spell_plan.GatedOnCaster(..)
    | spell_plan.GatedOnTarget(..) -> condition
  }
}

/// Which of the Proxies of a go start a child, with a debug line for each that
/// cannot be decided, and the rolls left (`gated`).
fn proxy_gates(
  proxies proxies: List(Proxy),
  subject subject: prerequisite.Subject,
  rolls rolls: List(Int),
) -> #(List(Proxy), List(Effect), List(Int)) {
  gated(
    rows: proxies,
    condition: fn(proxy: Proxy) { caster_side(condition: proxy.condition) },
    what: fn(proxy: Proxy) {
      "the Proxy to Spell4 " <> int.to_string(proxy.spell.spell4_id.value)
    },
    outcome: "so it is not started",
    subject:,
    rolls:,
  )
}

/// The rows whose condition lets them apply, in order, with a debug line for each the
/// server cannot decide, and the rolls left: a row with no gate applies, one gated on the
/// caster applies when every gate passes against the caster, and one behind a target apply
/// prerequisite does not (`condition_gate`).
fn gated(
  rows rows: List(row),
  condition condition: fn(row) -> spell_plan.Condition,
  what what: fn(row) -> String,
  outcome outcome: String,
  subject subject: prerequisite.Subject,
  rolls rolls: List(Int),
) -> #(List(row), List(Effect), List(Int)) {
  let #(applying, logs, rolls) =
    list.fold(rows, #([], [], rolls), fn(so_far, row) {
      let #(applying, logs, rolls) = so_far
      let #(gate, rolls) =
        condition_gate(
          condition: condition(row),
          subject:,
          rolls:,
          what: what(row),
          outcome:,
        )
      case gate {
        Starts -> #([row, ..applying], logs, rolls)
        GateFails -> #(applying, logs, rolls)
        CannotTell(why:) -> #(
          applying,
          [Log(level: LogDebug, text: why), ..logs],
          rolls,
        )
      }
    })
  #(list.reverse(applying), list.reverse(logs), rolls)
}

/// What a condition gives at a go: `what` names the effect in a debug line and
/// `outcome` says what follows when the server cannot decide.
fn condition_gate(
  condition condition: spell_plan.Condition,
  subject subject: prerequisite.Subject,
  rolls rolls: List(Int),
  what what: String,
  outcome outcome: String,
) -> #(ProxyGate, List(Int)) {
  case condition {
    spell_plan.Always -> #(Starts, rolls)
    spell_plan.GatedOnTarget(prerequisite_id:) -> #(
      CannotTell(
        why: what
        <> " applies only behind target prerequisite "
        <> int.to_string(prerequisite_id.value)
        <> ", which is not checked, "
        <> outcome,
      ),
      rolls,
    )
    // The plan gives only a Proxy a target gate it reads, and `proxy_gates` turns that
    // into its caster gates (`caster_side`) before this: a row of another kind that holds
    // one is refused, as a gate nothing here reads.
    spell_plan.GatedOnCasterAndTarget(target:, ..) -> #(
      CannotTell(
        why: what
        <> " applies only behind target prerequisite "
        <> int.to_string(prerequisite.id(prerequisite: target).value)
        <> ", which is not checked, "
        <> outcome,
      ),
      rolls,
    )
    spell_plan.GatedOnCaster(gates:) -> {
      let #(left, verdicts) =
        list.map_fold(gates, rolls, fn(rolls, gate) {
          let #(verdict, left) = checked(prerequisite: gate, subject:, rolls:)
          #(left, #(gate, verdict))
        })
      let not_read =
        list.find_map(verdicts, fn(decided) {
          case decided.1 {
            prerequisite.NotRead(prerequisite_type:) ->
              Ok(#(decided.0, prerequisite_type))
            prerequisite.Passes | prerequisite.Fails -> Error(Nil)
          }
        })
      let failed =
        list.any(verdicts, fn(decided) { decided.1 == prerequisite.Fails })
      case failed, not_read {
        True, _ -> #(GateFails, left)
        False, Error(Nil) -> #(Starts, left)
        False, Ok(#(gate, prerequisite_type)) -> #(
          CannotTell(
            why: what
            <> " is behind prerequisite "
            <> int.to_string(prerequisite.id(prerequisite: gate).value)
            <> " of type "
            <> int.to_string(prerequisite_type)
            <> ", which is not read, "
            <> outcome,
          ),
          left,
        )
      }
    }
  }
}

/// The gains a go gives (`Gain`), and a debug line for each it cannot: the spell's
/// own of the phase, then once each of the Proxies that start a child aimed at each
/// struck unit, which `starting` holds only when one unit was Hit.
fn gains_given(
  spell spell: Spell,
  phase phase: Int,
  starting starting: List(Proxy),
  subject subject: prerequisite.Subject,
  rolls rolls: List(Int),
  spent spent: Option(Int),
) -> #(List(Effect), List(Int)) {
  let #(rolls, given, logs) =
    list.fold(
      gains_of(spell:, phase:, proxies: starting, spent:),
      #(rolls, [], []),
      fn(so_far, gain) {
        let #(rolls, given, logs) = so_far
        let #(verdict, rolls) = gain_verdict(gain:, subject:, rolls:)
        case verdict {
          Given(gain: gift) -> #(rolls, [gift, ..given], logs)
          Withheld -> #(rolls, given, logs)
          NotApplied(why:) -> #(rolls, given, [
            Log(level: LogDebug, text: why),
            ..logs
          ])
        }
      },
    )
  let gains = case given {
    [] -> []
    [_, ..] -> [Gain(gains: list.reverse(given))]
  }
  #(list.append(list.reverse(logs), gains), rolls)
}

/// What becomes of one gain of a go.
type GainVerdict {
  Given(gain: class_resource.Gain)
  /// Its prerequisite fails.
  Withheld
  /// It cannot be given, and `why` says so in a debug line: a ticking gain, or a
  /// prerequisite of a type not read.
  NotApplied(why: String)
}

/// The gain given, withheld for a prerequisite that fails, or not applied, and the
/// rolls left after its prerequisite's check.
fn gain_verdict(
  gain gain: spell_plan.Gain,
  subject subject: prerequisite.Subject,
  rolls rolls: List(Int),
) -> #(GainVerdict, List(Int)) {
  let effect = int.to_string(gain.effect_id.value)
  case gain {
    spell_plan.TickingGain(..) -> #(
      NotApplied(
        why: "the ticking gain of Spell4Effects " <> effect <> " is not applied",
      ),
      rolls,
    )
    spell_plan.Gain(prerequisite: None, slot:, amount:, ..) -> #(
      Given(gain: class_resource.Gain(slot:, amount:)),
      rolls,
    )
    spell_plan.Gain(prerequisite: Some(gate), slot:, amount:, ..) -> {
      let #(verdict, rolls) = checked(prerequisite: gate, subject:, rolls:)
      #(
        gate_verdict(
          verdict:,
          gate:,
          effect:,
          gift: class_resource.Gain(slot:, amount:),
        ),
        rolls,
      )
    }
  }
}

/// What a gain's prerequisite makes of the gain.
fn gate_verdict(
  verdict verdict: prerequisite.Verdict,
  gate gate: prerequisite.Prerequisite,
  effect effect: String,
  gift gift: class_resource.Gain,
) -> GainVerdict {
  case verdict {
    prerequisite.Passes -> Given(gain: gift)
    prerequisite.Fails -> Withheld
    prerequisite.NotRead(prerequisite_type:) ->
      NotApplied(
        why: "the gain of Spell4Effects "
        <> effect
        <> " is behind prerequisite "
        <> int.to_string(prerequisite.id(prerequisite: gate).value)
        <> " of type "
        <> int.to_string(prerequisite_type)
        <> ", which is not read, so it is not given",
      )
  }
}

/// Whether a go clears the caster's current cast (`cast.current_cast`): a cast with
/// a cast bar, a cast time and no parent clears whichever cast is current, unless
/// its method is Channeled, PressHold, ChanneledField, ChargeRelease or
/// Multiphase; any other cast clears it only when it is the current cast, has no
/// channel and is not PressHold, ChargeRelease or Multiphase.
fn clears_current(
  cast cast: State,
  live live: Live,
  cast_id cast_id: Int,
) -> Bool {
  use <- bool.guard(when: cast.passive == Some(cast_id), return: False)
  let spell = live.spell
  let clears_whichever = case spell.method {
    spell_plan.Normal
    | spell_plan.ClientSideInteraction
    | spell_plan.RapidTap
    | spell_plan.Transactional
    | spell_plan.OtherMethod(..) ->
      spell.cast_time_ms != 0
      && live.parent == None
      && spell_plan.shows_cast_bar(
        spell:,
        pressed: live.root == spell.spell4_id,
      )
    spell_plan.Channeled
    | spell_plan.PressHold
    | spell_plan.ChanneledField
    | spell_plan.ChargeRelease
    | spell_plan.Multiphase -> False
  }
  let clears_itself = case spell.method {
    spell_plan.Normal
    | spell_plan.Channeled
    | spell_plan.ChanneledField
    | spell_plan.ClientSideInteraction
    | spell_plan.RapidTap
    | spell_plan.Transactional
    | spell_plan.OtherMethod(..) ->
      cast.current == Some(cast_id) && option.is_none(spell.channel)
    spell_plan.PressHold | spell_plan.ChargeRelease | spell_plan.Multiphase ->
      False
  }
  clears_whichever || clears_itself
}

/// The units a round Hit, in the round's order; a deflect is none of them.
pub fn hit_units(struck struck: List(Struck)) -> List(Int) {
  list.filter_map(struck, fn(one) {
    case one {
      Hit(unit_id:, ..) -> Ok(unit_id)
      Deflected(..) -> Error(Nil)
    }
  })
}

/// A Proxy of a go: a Proxy aimed at the area starts one child for each Hit unit of
/// the round and none for a deflect, any other starts one on the caster. A Proxy behind a
/// target gate starts a child on a unit only when the gate passes against that unit, once
/// for each unit, with no roll (`target_gate`).
fn children(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  live live: Live,
  proxy proxy: Proxy,
  struck struck: List(Struck),
  subject subject: prerequisite.Subject,
  poses poses: Dict(Int, area.Pose),
) -> #(State, List(Effect)) {
  let targets = case proxy.target {
    spell_plan.OnCaster -> [caster.unit_id]
    spell_plan.OnEachStruck -> hit_units(struck:)
  }
  list.fold(targets, #(cast, []), fn(so_far, primary_target) {
    let #(cast, effects) = so_far
    case target_gate(proxy:, caster:, primary_target:, subject:, poses:) {
      Starts -> {
        let #(cast, more) =
          child(cast:, caster:, now_ms:, live:, proxy:, primary_target:)
        #(cast, list.append(effects, more))
      }
      GateFails -> #(cast, effects)
      CannotTell(why:) -> #(
        cast,
        list.append(effects, [Log(level: LogDebug, text: why)]),
      )
    }
  })
}

/// What a Proxy's target gate gives for the unit its child would be made on. The gate's
/// first unit is that unit and its second the caster
/// (`Spell4Effects.prerequisiteIdTargetApply`): a struck unit as the caster's picture
/// shows it (`of_struck`, so a unit with no pose leaves a type 108 condition not read), or
/// the caster for a Proxy aimed at it, which stands on its own point, as `subject` has it.
/// A Proxy with no target gate starts. The plan gives a Proxy no condition but `Always`,
/// `GatedOnCaster` and `GatedOnCasterAndTarget`; a Proxy that holds `GatedOnTarget`, which
/// it never builds for one, is refused, as a gate nothing reads.
fn target_gate(
  proxy proxy: Proxy,
  caster caster: Caster,
  primary_target primary_target: Int,
  subject subject: prerequisite.Subject,
  poses poses: Dict(Int, area.Pose),
) -> ProxyGate {
  case proxy.condition {
    spell_plan.GatedOnCasterAndTarget(target:, ..) -> {
      let gate_subject = case proxy.target {
        spell_plan.OnCaster -> subject
        spell_plan.OnEachStruck ->
          prerequisite.of_struck(
            first: option.from_result(dict.get(poses, primary_target)),
            second: area.pose_of(place: caster.place),
            quests: caster.quests,
          )
      }
      case prerequisite.check(prerequisite: target, subject: gate_subject) {
        prerequisite.Passes -> Starts
        prerequisite.Fails -> GateFails
        prerequisite.NotRead(prerequisite_type:) ->
          CannotTell(
            why: "the Proxy to Spell4 "
            <> int.to_string(proxy.spell.spell4_id.value)
            <> " on unit "
            <> int.to_string(primary_target)
            <> " is behind target prerequisite "
            <> int.to_string(prerequisite.id(prerequisite: target).value)
            <> " of type "
            <> int.to_string(prerequisite_type)
            <> ", which is not read, so it is not started",
          )
      }
    }
    spell_plan.GatedOnTarget(prerequisite_id:) ->
      CannotTell(
        why: "the Proxy to Spell4 "
        <> int.to_string(proxy.spell.spell4_id.value)
        <> " is behind target prerequisite "
        <> int.to_string(prerequisite_id.value)
        <> ", which the plan keeps unchecked, so it is not started",
      )
    spell_plan.Always | spell_plan.GatedOnCaster(..) -> Starts
  }
}

/// One child of a Proxy: it starts at once for no delay, else after it from a timer
/// of its own. The Proxy's gate has passed at the go (`proxy_gates`).
fn child(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  live live: Live,
  proxy proxy: Proxy,
  primary_target primary_target: Int,
) -> #(State, List(Effect)) {
  case proxy.delay_ms > 0 {
    False ->
      start(
        cast:,
        caster:,
        now_ms:,
        spell: proxy.spell,
        root: live.root,
        parent: Some(live.spell.spell4_id),
        primary_target:,
        client_cast_id: None,
        role: Child,
        spent: None,
        reserved: [],
      )
    True -> {
      let #(cast, _, start) =
        armed(
          cast:,
          due: StartChild(
            root: live.root,
            parent: live.spell.spell4_id,
            primary_target:,
            proxy:,
          ),
          after_ms: proxy.delay_ms,
        )
      #(cast, [start])
    }
  }
}

/// A live cast ends: 0x7fe to the caster and the audience, and the cast is no
/// longer live nor the caster's current cast. A channel starts its cooldown here
/// too (`0x14053e1b0`), and a stage that closes its ability's threshold does that
/// after its 0x7fe.
fn finish(
  cast cast: State,
  cast_id cast_id: Int,
  live live: Live,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, closed) = finish_steps(cast:, cast_id:, live:, now_ms:)
  #(
    passive_cleared(cast:, cast_id:),
    list.append(finished_effects(cast_id:, audience: live.audience), closed),
  )
}

/// The cast without the innate passive's id when the cast `cast_id` is the passive and
/// has left both `casts` and `lingering`, so that no later cast the caster mints the
/// same id for is taken for the passive.
fn passive_cleared(cast cast: State, cast_id cast_id: Int) -> State {
  use <- bool.guard(when: cast.passive != Some(cast_id), return: cast)
  State(..cast, passive: None)
}

/// Every step of a live cast's end but its 0x7fe: the cast is no longer live nor the
/// caster's current cast, a channel starts its cooldown (`0x14053e1b0`), and a stage
/// that closes its ability's threshold does that, with what the close writes.
fn finish_steps(
  cast cast: State,
  cast_id cast_id: Int,
  live live: Live,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let cast =
    State(
      ..cast,
      casts: dict.delete(cast.casts, cast_id),
      current: case cast.current == Some(cast_id) {
        True -> None
        False -> cast.current
      },
    )
  let cast = case live.spell.method, live.spell.cooldown_phase {
    spell_plan.Channeled, _ -> start_cooldown(cast:, spell: live.spell, now_ms:)
    spell_plan.Multiphase, Some(phase) if live.gone > phase ->
      start_cooldown(cast:, spell: live.spell, now_ms:)
    spell_plan.Multiphase, _ -> cast
    spell_plan.Normal, _
    | spell_plan.PressHold, _
    | spell_plan.ChanneledField, _
    | spell_plan.ClientSideInteraction, _
    | spell_plan.RapidTap, _
    | spell_plan.ChargeRelease, _
    | spell_plan.Transactional, _
    | spell_plan.OtherMethod(..), _
    -> cast
  }
  case live.stage_of, live.closes_threshold {
    Some(ability), True -> close_threshold(cast:, ability:, now_ms:)
    Some(_), False | None, True | None, False -> #(cast, [])
  }
}

/// A live cast that has gone for the last time ends, or lingers when a node of it
/// still has life: every step of its end runs, and only its 0x7fe waits until its
/// last node ends (`cast.target_node_end`). A node whose life is over when the cast
/// starts to linger is written 0x811 at once. The innate passive's cast lingers even
/// when no node of it lives, so it ends with no 0x7fe, and only when its last node is
/// taken off.
fn finish_or_linger(
  cast cast: State,
  cast_id cast_id: Int,
  live live: Live,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(ended, kept) = ended_and_kept(nodes: live.nodes, now_ms:)
  case kept, cast.passive == Some(cast_id) {
    [], False -> finish(cast:, cast_id:, live:, now_ms:)
    [], True | [_, ..], _ -> {
      let #(cast, closed) = finish_steps(cast:, cast_id:, live:, now_ms:)
      let cast =
        State(
          ..cast,
          lingering: dict.insert(
            cast.lingering,
            cast_id,
            Lingering(
              spell: live.spell,
              audience: live.audience,
              started_ms: live.started_ms,
              primary_target: live.primary_target,
              nodes: dict.from_list(kept),
            ),
          ),
        )
      let #(cast, armed) = rearmed(cast:, cast_id:, now_ms:)
      let expired = case ended {
        [] -> []
        [_, ..] ->
          targets_removed_effects(
            cast_id:,
            unit_ids: sorted_units(ended),
            audience: live.audience,
            destroyed: False,
          )
      }
      #(cast, list.flatten([expired, armed, closed]))
    }
  }
}

/// The next timer's id, and the state counting it.
/// The timer of `due` started to fire after `after_ms`: the state that keeps it, its id
/// and the effect that starts it.
fn armed(
  cast cast: State,
  due due: Due,
  after_ms after_ms: Int,
) -> #(State, TimerId, Effect) {
  let #(cast, timer) = new_timer(cast:)
  #(
    State(..cast, timers: dict.insert(cast.timers, timer, due)),
    timer,
    StartTimer(timer:, after_ms:),
  )
}

fn new_timer(cast cast: State) -> #(State, TimerId) {
  #(
    State(..cast, timers_started: cast.timers_started + 1),
    TimerId(first_timer + cast.timers_started),
  )
}

fn position_of(place place: Place) -> SpellPosition {
  SpellPosition(
    x: float32.to_bits(start_place.x(place)),
    y: float32.to_bits(start_place.y(place)),
    z: float32.to_bits(start_place.z(place)),
  )
}

fn yaw_of(place place: Place) -> Int {
  float32.to_bits(start_place.facing(place).yaw)
}

/// 0x7ff for a cast that starts: the caster is its own primary target
/// (`Spell4TargetMechanics.targetType`), the lists are empty (`spell.empty_lists`)
/// and the 16-bit value and the two bits are the decode's safe values
/// (`opcode.0x7ff.caster_item_level`, `opcode.0x7ff.own_cast`,
/// `opcode.0x7ff.activate`).
fn started_message(
  id id: Int,
  spell spell: Spell,
  root root: Spell4Id,
  parent parent: Option(Spell4Id),
  primary_target primary_target: Int,
  caster caster: Caster,
) -> SpellStarted {
  SpellStarted(
    cast_id: id,
    spell4_id: spell.spell4_id.value,
    root_spell4_id: root.value,
    parent_spell4_id: case parent {
      Some(parent) -> parent.value
      None -> 0
    },
    caster_unit_id: caster.unit_id,
    field_6: 0,
    primary_target_unit_id: primary_target,
    position: position_of(place: caster.place),
    yaw: yaw_of(place: caster.place),
    initial_positions: [],
    telegraph_positions: [],
    field_12: 1,
    field_13: 0,
  )
}

/// 0x7f4 for a go: a target info for each Hit unit in the order of the round, with
/// target flags 0 (`opcode.0x7f4.target_info`), each with the damage that landed, no
/// position and no missile (`opcode.0x7f4`, `spell.empty_lists`). A deflected unit has
/// no info: the 0x7fb shows it.
fn go_message(
  cast_id cast_id: Int,
  phase phase: Int,
  place place: Place,
  struck struck: List(Struck),
  listed listed: List(#(Int, List(Listed))),
) -> SpellGo {
  let hits =
    list.filter_map(struck, fn(one) {
      case one {
        Hit(unit_id:, descriptions:, ..) -> Ok(#(unit_id, descriptions))
        Deflected(..) -> Error(Nil)
      }
    })
  let unstruck =
    list.filter(listed, fn(entry) {
      result.is_error(list.key_find(hits, entry.0))
    })
    |> list.map(fn(entry) { #(entry.0, []) })
  SpellGo(
    cast_id:,
    ignore_cooldown: 0,
    destination: position_of(place:),
    targets: list.append(hits, unstruck)
      |> list.index_map(fn(hit, index) {
        target_info(
          index:,
          unit_id: hit.0,
          descriptions: hit.1,
          listed: list.key_find(listed, hit.0) |> result.unwrap([]),
        )
      }),
    initial_positions: [],
    telegraph_positions: [],
    missiles: [],
    phase:,
  )
}

/// The refusal of a press that names no ability, or no stage left of one: result 4
/// (`0x14039a040`), the same answer to a 0x9a and to a 0x4db.
fn refused_unknown(
  client_cast_id client_cast_id: Int,
  spell4_id spell4_id: Int,
) -> Effect {
  refused(client_cast_id:, spell4_id:, result: cast_result.SpellUnknown)
}

fn refused(
  client_cast_id client_cast_id: Int,
  spell4_id spell4_id: Int,
  result result: cast_result.CastResult,
) -> Effect {
  let assert Ok(body) =
    spell_cast_refused.encode(SpellCastRefused(
      client_cast_id:,
      spell4_id:,
      result:,
    ))
    as "a cast id of 32 bits, a Spell4 id of 18 and a result of 9 fit the message"
  Send(frame: Frame(message_id: spell_cast_refused.message_id, body:))
}

/// 0x07FD for the press's cast: the client's id, the server's, the caster as its
/// primary target and the position and yaw the 0x7ff holds.
fn confirmed_frame(
  client_cast_id client_cast_id: Int,
  start start: SpellStarted,
) -> Frame {
  let assert Ok(body) =
    spell_cast_confirmed.encode(
      SpellCastConfirmed(
        client_cast_id:,
        server_cast_id: start.cast_id,
        primary_target_unit_id: start.primary_target_unit_id,
        position: start.position,
        yaw: start.yaw,
        initial_positions: [],
        telegraph_positions: [],
      ),
    )
    as "a cast id of 32 bits and floats fit the message, and the rule sends no list"
  Frame(message_id: spell_cast_confirmed.message_id, body:)
}

/// 0x0816 for a threshold that opens: the ability's spell as the opened and the
/// resolving spell, 0 for the third (the opened spell's own cooldowns), and the
/// base cast's id as the value the client sends back (`opcode.0x816`).
fn opened_frame(spell4_id spell4_id: Spell4Id, cast_id cast_id: Int) -> Frame {
  let assert Ok(body) =
    spell_threshold_opened.encode(SpellThresholdOpened(
      spell4_id: spell4_id.value,
      resolving_spell4_id: spell4_id.value,
      cooldown_spell4_id: 0,
      cancel_cast_id: cast_id,
    ))
    as "Spell4 ids of 18 bits and a cast id of 32 fit the message"
  Frame(message_id: spell_threshold_opened.message_id, body:)
}

/// 0x0817 for the index the next press casts (`opcode.0x817`).
fn index_frame(spell4_id spell4_id: Spell4Id, index index: Int) -> Frame {
  let assert Ok(body) =
    spell_threshold_index.encode(SpellThresholdIndex(
      spell4_id: spell4_id.value,
      index:,
    ))
    as "a Spell4 id of 18 bits and a stage index of 8 fit the message"
  Frame(message_id: spell_threshold_index.message_id, body:)
}

/// 0x0814 for a threshold that closes, with the bit that starts the cooldowns
/// (`opcode.0x814`).
fn closed_frame(
  spell4_id spell4_id: Spell4Id,
  start_cooldowns start_cooldowns: Int,
) -> Frame {
  let assert Ok(body) =
    spell_threshold_closed.encode(SpellThresholdClosed(
      spell4_id: spell4_id.value,
      start_cooldowns:,
    ))
    as "a Spell4 id of 18 bits and a bit fit the message"
  Frame(message_id: spell_threshold_closed.message_id, body:)
}

/// 0x7ff for a creature's cast of its attack spell on its target, from where it
/// stands: the target is the cast's primary target, the spell its own root, and the
/// lists and the safe values are a player's cast's (`started_message`).
pub fn creature_started(
  cast_id cast_id: Int,
  spell4_id spell4_id: Int,
  caster_unit_id caster_unit_id: Int,
  target_unit_id target_unit_id: Int,
  place place: Place,
) -> SpellStarted {
  SpellStarted(
    cast_id:,
    spell4_id:,
    root_spell4_id: spell4_id,
    parent_spell4_id: 0,
    caster_unit_id:,
    field_6: 0,
    primary_target_unit_id: target_unit_id,
    position: position_of(place:),
    yaw: yaw_of(place:),
    initial_positions: [],
    telegraph_positions: [],
    field_12: 1,
    field_13: 0,
  )
}

/// 0x7f4 for the one go, phase 0, of a creature's cast, with the units its round
/// struck, as a player's go is written (`go_message`).
pub fn creature_went(
  cast_id cast_id: Int,
  place place: Place,
  struck struck: List(Struck),
) -> SpellGo {
  go_message(cast_id:, phase: 0, place:, struck:, listed: [])
}

/// 0x7fb for the units a creature's go missed, or none (`missed_message`).
pub fn creature_missed(
  cast_id cast_id: Int,
  struck struck: List(Struck),
) -> Option(SpellMissed) {
  missed_message(cast_id:, struck:)
}

/// 0x07FF for a cast that starts, which the caster's rule tells each viewer as
/// news and each viewer's connection writes the same way.
pub fn started_frame(start start: SpellStarted) -> Frame {
  let assert Ok(body) = spell_started.encode(start)
    as "a cast id of 32 bits, Spell4 ids of 18 and a unit id of 32 fit the message, and the rule sends no list"
  Frame(message_id: spell_started.message_id, body:)
}

/// 0x07F4 for a cast that goes off, written by the caster's rule and by each
/// viewer's connection the same way.
pub fn went_frame(go go: SpellGo) -> Frame {
  let assert Ok(body) = spell_go.encode(go)
    as "a cast id of 32 bits and a phase of 8 fit the message, and the rule sends no list"
  Frame(message_id: spell_go.message_id, body:)
}

/// 0x07FE for a cast that ends, written by the caster's rule and by each
/// viewer's connection the same way (`opcode.0x7fe`).
pub fn finished_frame(cast_id cast_id: Int) -> Frame {
  let assert Ok(body) = spell_finished.encode(SpellFinished(cast_id:))
    as "a cast id of 32 bits fits the message"
  Frame(message_id: spell_finished.message_id, body:)
}

/// 0x0811 for a cast taken off some units, written by the caster's rule and by each
/// viewer's connection the same way (`opcode.0x811`).
pub fn targets_removed_frame(removed removed: SpellTargetsRemoved) -> Frame {
  let assert Ok(body) = spell_targets_removed.encode(removed)
    as "a cast id of 32 bits and at most a few unit ids of 32 fit the message"
  Frame(message_id: spell_targets_removed.message_id, body:)
}

/// 0x0813 for a cast that loses one stack on a unit, written by the caster's rule and
/// by each viewer's connection the same way (`opcode.0x813`).
pub fn stack_removed_frame(removed removed: SpellStackRemoved) -> Frame {
  let assert Ok(body) = spell_stack_removed.encode(removed)
    as "a cast id and a unit id of 32 bits fit the message"
  Frame(message_id: spell_stack_removed.message_id, body:)
}

/// A sentence that says what the client sent that is refused, for the log.
pub fn describe(refusal refusal: Refusal) -> String {
  case refusal {
    NotDecoded(undecoded:) -> client_connection.describe_undecoded(undecoded:)
    NoClientCastId ->
      "0x009A names the client's cast id 0, which its counter never gives"
    UnknownCancel(reason:, bit:) ->
      "0x0801 holds the reason "
      <> int.to_string(reason)
      <> " and the bit "
      <> int.to_string(bit)
      <> ", which the client never sends together"
  }
}

/// One struck unit's info in a go: its place in the list, target flags 0
/// (`opcode.0x7f4.target_info`), the combat result of the strike, and an effect
/// info for each landed blow with its damage description and delay. The instance
/// count and the effects' instance ids number from 1 (kept by the client, no reader
/// traced), except a crowd-control state's, which is the id its tell gave
/// (genesis_prime/game/crowd_control `instance_id`).
fn target_info(
  index index: Int,
  unit_id unit_id: Int,
  descriptions descriptions: List(hit.Description),
  listed listed: List(Listed),
) -> SpellTargetInfo {
  SpellTargetInfo(
    unit_id:,
    index:,
    flags: 0,
    instance_count: 1,
    combat_result: case
      list.any(descriptions, fn(description) {
        description.damage.combat_result == combat_result.Critical
      })
    {
      True -> combat_result.Critical
      False -> combat_result.Hit
    },
    effects: list.append(
      list.index_map(descriptions, fn(description, effect_index) {
        SpellEffectInfo(
          spell4_effects_id: description.spell4_effects_id,
          instance_id: effect_index + 1,
          delay_ms: description.delay_ms,
          field_4: 0,
          result: spell_effect_result.Damage(SpellEffectDamage(
            description: description.damage,
          )),
        )
      }),
      list.index_map(listed, fn(effect, effect_index) {
        SpellEffectInfo(
          spell4_effects_id: effect.effect_id.value,
          instance_id: option.unwrap(
            effect.instance_id,
            list.length(descriptions) + effect_index + 1,
          ),
          delay_ms: effect.delay_ms,
          field_4: 0,
          result: case effect.damage {
            Some(description) ->
              spell_effect_result.Damage(SpellEffectDamage(description:))
            None -> spell_effect_result.Bit(SpellEffectBit(field_2: 0))
          },
        )
      }),
    ),
  )
}

/// 0x7fb for the deflected units of a go, or none when none was deflected: each
/// entry has reason 0 (Dodge, which the client shows as Deflect) and time 0
/// (`opcode.0x7fb`, `opcode.0x7fb.time`).
fn missed_message(
  cast_id cast_id: Int,
  struck struck: List(Struck),
) -> Option(SpellMissed) {
  case
    list.filter_map(struck, fn(one) {
      case one {
        Deflected(unit_id:) ->
          Ok(SpellMiss(unit_id:, reason: miss_reason.Dodge, time_ms: 0))
        Hit(..) -> Error(Nil)
      }
    })
  {
    [] -> None
    misses -> Some(SpellMissed(cast_id:, misses:))
  }
}

/// 0x07FB for a cast whose targets were missed, written by the caster's rule and by
/// each viewer's connection the same way.
pub fn missed_frame(missed missed: SpellMissed) -> Frame {
  let assert Ok(body) = spell_missed.encode(missed)
    as "a cast id of 32 bits, a unit id of 32 and a reason of 4 fit the message"
  Frame(message_id: spell_missed.message_id, body:)
}
